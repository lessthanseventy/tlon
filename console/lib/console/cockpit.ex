defmodule Console.Cockpit do
  @moduledoc """
  The live loop and the cockpit's one brain (design §8). It *is* the dispatcher: termbox2 paints
  (output-only), `Raxol.Terminal.Driver` feeds it `:key`/`:resize` events as GenServer casts, and
  `Server.Bus` events arrive as plain messages. Every input, resize, Bus event, and tick reloads
  the server reads and repaints. Holds the only shared state — the active space and the focused
  thread (§8) — and caches nothing about tmux past the paint (§5).

  The GenServer keeps the callbacks and `apply_effect/2` (the keymap's effects); the work behind
  them lives in `Console.Reads` (the frame's data), `Console.Staffing` (find-or-spawn),
  `Console.Delivery` (event → coworker), `Console.Cockpit.Author` / `Boards` (menus, workspace
  CRUD, the boards) and `Console.Cockpit.Recovery` (the run loop around this process).

  Not supervised at app boot: it grabs the TTY, so it runs only under `mix console.run` in a real
  terminal, never during `mix test`.
  """
  use GenServer

  alias Console.Board
  alias Console.Cockpit.Author
  alias Console.Cockpit.Boards
  alias Console.Cockpit.Recovery
  alias Console.Delivery
  alias Console.Keymap
  alias Console.Mouse
  alias Console.Osc
  alias Console.Panel
  alias Console.Reads
  alias Console.Safe
  alias Console.Server.Channel
  alias Console.Server.Dossier
  alias Console.Sessions
  alias Console.Space
  alias Console.Staffing
  alias Console.Terminal
  alias Console.Tlon.Focus
  alias Console.Tmux
  alias Console.View
  alias Console.WorkspaceTemplates
  alias Ghostty.KeyEvent
  alias Raxol.Core.Events.Event
  alias Server.Bus

  # `Space.workspace?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

  @doc "Start the cockpit and block until the operator quits — the entry point `mix console.run` calls."
  @spec run() :: :ok
  defdelegate run, to: Recovery

  # Redraw cadence for tmux liveness + roster warmth, independent of Bus events.
  @tick_ms 500
  # Coalesce a burst of terminal events (pi streaming, tmux output) into ONE render on this
  # cadence, instead of rendering per-event. During streaming the embedded terminal fires
  # hundreds of events/sec; rendering each starves key casts queued behind them in the
  # mailbox. ~8ms ≈ 120fps — one frame of output latency, and terminal-event handling
  # becomes a cheap no-op once a render is armed, so the mailbox drains and input lands now.
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  # TB_INPUT_ESC (1) | TB_INPUT_MOUSE (4) = 5 (termbox2.h §309–313): keep ESC-sequence parsing AND
  # emit mouse events, which the Driver translates into Event{type: :mouse, data: %{x, y, button}}.
  @tb_input_esc_mouse 5

  # Kitty keyboard protocol: push flags + set disambiguate (CSI > 1 u) at init; `Recovery.pop_modes/0`
  # pops it at teardown. See the init comment for the full shifted-key round-trip.
  @kitty_enable "\e[>1u"

  # Bracketed paste: enable (\e[?2004h) at init so ghostty wraps a paste in \e[200~…\e[201~
  # (disabled at teardown). Without it a paste reaches raxol's InputParser one char at a time and
  # every newline submits; with it the cockpit's paste buffer forwards the whole block.
  @paste_enable "\e[?2004h"

  # Button-motion mouse tracking (\e[?1002h): report mouse MOTION while a button is held, not just
  # press/release. The raxol Driver enables only 1000 (button) + 1006 (SGR); without 1002 ghostty
  # sends nothing during a drag, so a Tlön text selection only highlights on mouseup. Enabled here
  # (additive to the Driver's modes, written after it starts); teardown's reset already clears 1002.
  @mouse_motion_enable "\e[?1002h"

  @impl true
  def init(_opts) do
    # Subscribe before the first read so nothing posted mid-boot is missed.
    Bus.subscribe_sessions()
    Bus.subscribe_threads()
    # Explicit thinking/idle declarations (server:presence) — the "typing" indicator's rich half.
    Bus.subscribe_presence()
    # The global activity topic is a strict superset of messages_topic for `:message_posted`
    # (Bus.broadcast always publishes a message to both) — subscribing to messages_topic too
    # would double-deliver every message. Riding activity alone also brings fact_banked /
    # event_recorded / issue_raised / question_raised in globally (the Activity feed's buffer),
    # not just for the focused thread.
    Bus.subscribe_activity()
    Bus.subscribe_habits()

    case :termbox2_nif.tb_init() do
      0 ->
        # Trap exits so a crash anywhere — this server, or the linked Driver — runs terminate/2,
        # which restores the host tty (Kitty pop + tb_shutdown). Without this, a raise mid-callback
        # leaves the shell in alt-screen + mouse-reporting + Kitty mode until a manual `reset`.
        Process.flag(:trap_exit, true)
        :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
        :termbox2_nif.tb_set_input_mode(@tb_input_esc_mouse)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())
        # Watch every session terminal — the `s` verb AND the arbiter's autonomous spawn repaint
        # through this cockpit, whoever started them.
        Sessions.observe(self())

        # Enable Kitty keyboard disambiguate mode (CSI >1u) on the host tty so shift+enter etc.
        # arrive with modifiers intact (raxol's self-healed InputParser decodes \e[<cp>;<mods>u —
        # see mix.exs) instead of degrading to a bare \r. Popped in teardown; harmless on a
        # non-Kitty host (the push is simply ignored).
        IO.write(@kitty_enable)
        # Enable bracketed paste (\e[?2004h) so ghostty wraps a paste in \e[200~…\e[201~ and the
        # cockpit's paste buffer can forward it as one block instead of per-keystroke decoding.
        IO.write(@paste_enable)
        # Enable button-motion tracking (\e[?1002h) so a drag streams motion, not just press/release
        # — the Tlön selection highlights live instead of only on mouseup. See @mouse_motion_enable.
        IO.write(@mouse_motion_enable)

        state =
          render(%{
            driver: driver,
            w: max(:termbox2_nif.tb_width(), 1),
            h: max(:termbox2_nif.tb_height(), 1),
            active_key: List.first(Space.all()).key,
            focused_id: nil,
            threads: [],
            # The rail's last painted rows (`reads.sidebar`) — what the keyboard resolves against.
            sidebar: [],
            # Orbis' focus toggle (`h`/`l`) — which cursor its j/k drives: the survey's per-row
            # cursor (default, so a fresh Orbis opens ready to zoom a workspace) or the thread list.
            orbis_focus: :survey,
            # The Orbis survey's per-row cursor (j/k), clamped to the live workspace count at keypress
            # time (Console.Keymap) — `Enter`/click resolve it to that row's workspace id.
            survey_cursor: 0,
            # Orbis' second face (D2.1): `:survey` (Overview, the default) or `:author` (Panel.Author
            # — create/delete server workspaces). `a` toggles; Esc in `:author` steps back.
            orbis_face: :survey,
            # The author face's own per-row cursor (j/k), clamped to `Console.Workspaces.all/0`'s length
            # at keypress time — mirrors `survey_cursor`.
            author_cursor: 0,
            # The author face's delete confirm arm (D2.5): the workspace id a `d` press armed, or nil.
            # A second `d` on this SAME id confirms; any other key cancels (Console.Keymap).
            pending_delete: nil,
            # Tlön nav's delete confirm arm: the `{kind, payload, label}` a `d` press resolved
            # (MEMORY fact / LEAVES leaf), or nil. Second `d` confirms; any other key cancels.
            tlon_delete: nil,
            # The tertius y/n confirm arm (Slice 3.5): `%{action, ctx, summary}` when a consequential
            # verb (open work / approve a gate) is routed and waiting on the operator, else nil. `y`
            # fires `Console.Orchestrator.confirm/2`; any other key cancels (Console.Keymap gate).
            pending_confirm: nil,
            # The /status readout (reshape slice D): a %{title, lines} MAIN detail while the
            # composer command has it open, else nil. Cleared by any pane Enter (:tlon_enter);
            # Esc closes it through the ordinary detail mode.
            status_detail: nil,
            # The Workspace center's face: the THREAD STACK (:chat, the default now — Slice 3, no
            # more `v`-to-find-it) or the live PTY (:terminal, still reachable). The stack is home.
            center_view: :chat,
            # Two-step center (2026-09-01): nil = the thread LIST; an id = that thread's CONVERSATION
            # (scrollable, text-selectable). Enter opens, Esc goes back — replaces the fold/zoom stack.
            opened_thread: nil,
            # The list cursor's thread id, recomputed each render (focused-if-in-stack else first) and
            # stashed so open/move effects can target it between renders.
            stack_focus: nil,
            # The field editor's own state (D2.4 Chunk 2a): `%{id, field, sub, mode}` while `e` has
            # opened it, else nil. VIEW cursors only — the workspace's data lives in server and is
            # re-read from `Console.Workspaces.all/0` every render (Console.Keymap).
            author_edit: nil,
            subscribed_thread: nil,
            leader_pending?: false,
            # LOCK mode (design 2026-08-23): Alt+g total-passthrough to the center — every other
            # key, Alt chords included, forwards raw so readline/emacs keep their bindings.
            lock?: false,
            # Tlön's lazygit focus (which sidebar column/pane/section, and whether we're in the
            # center tmux terminal). Persistent across keypresses — the keymap reads+advances it,
            # only in the Tlön space. Defaults in-terminal, so Tlön opens with keys going to tmux.
            focus: Focus.new(),
            # The last acted-on left-click cell — raxol's event_translator gives mouse events NO
            # press/release action, so a click arrives as TWO identical `:left` events; we act on the
            # first and swallow the immediate duplicate (the release). Any other mouse event clears it.
            last_left: nil,
            # Right-click also arrives as a press+release pair (no action) — dedup the same way, else
            # the release re-hits the just-opened menu and closes it.
            last_right: nil,
            # The open overlay menu (right-click workspace context menu / icon picker), or nil.
            menu: nil,
            # The open full-screen board (`:tickets` / `:notes`, Slice 3.5), or nil.
            board: nil,
            # The Tickets kanban cursor `{col, row}` (Slice D3) — reset when a board opens.
            board_cursor: {0, 0},
            # The STACK-zoom embedded lazygit (Slice 4): `%{thread_id, path}` while a full-screen
            # `lazygit` PTY is up over the focused thread's worktree, else nil. The terminal itself
            # lives in `Console.Sessions` keyed `{:lazygit, thread_id}`; this only marks the overlay.
            lazygit: nil,
            # The toggleable right SESSION PANE (2026-08-31): true = show the selected thread's live
            # lead PTY in a right column beside the thread stack. The target follows the stack cursor;
            # the terminal lives in `Console.Sessions` keyed `{:session, thread_id}`. Alt+\ toggles.
            session_pane: false,
            paste_buffer: nil,
            input: nil,
            flash: nil,
            # The tertius band's receipt log (Slice 3): the last few dispatches, newest-first.
            receipts: [],
            # Hot-reload trigger tracking: `console:reload` (a separate process) recompiles + touches
            # `.reload`; the cockpit reloads Console.* modules on the next tick. `:unset` until the
            # first tick records the baseline (so boot never reloads). Edit → reload without restart.
            reload_seen: :unset,
            scrolls: %{},
            placements: [],
            render_scheduled?: false,
            stack: nil,
            health: nil,
            # The Memory pane's read (coverage + pinned + pending habits), cached with stack/health;
            # invalidated on a habit approve/reject so the pane reflects the write immediately.
            memory: nil,
            # The Orbis rollup (`Console.Orbis.rollup/0`) the survey reads, cached on the probe cadence so
            # the keymap's survey cursor can clamp against it at keypress time.
            leaves: nil,
            # The server activity feed's bounded buffer (Tlön right sidebar + the footer pulse):
            # `{tag, row}` Bus events, newest-first, capped at 50 by `push_activity/3`. Seeded from
            # the durable logs so a fresh cockpit's NOW isn't blank until new events flow (the ring
            # itself is in-memory — this backfill is the restart fix); live Bus events prepend onto it.
            activity: Reads.seed_activity(),
            # The active workspace's thread ids (cached on the probe cadence) — the global activity
            # feed is filtered to these so NOW shows only this workspace's events. nil = unfiltered.
            ws_thread_ids: nil,
            # The NOW pane's standing ATTENTION list (Slice 4D): parked worklines awaiting the
            # operator, cached with the other probes (@probe_ms) so the pane never reads server
            # per-frame. Filled by `gates_read/0` in a workspace; nil→[] elsewhere.
            gates: [],
            # Recently-seen `{tag, id}` keys (capped ~100) — the first-sight gate. A tagged event on
            # the FOCUSED thread arrives TWICE (its thread topic + the global activity topic), so this
            # dedupes side effects (notify/nudge/append) to exactly once. See `fresh?/3`.
            seen_events: [],
            probed_at: 0,
            machine_retry_at: nil,
            # The standing center coworker's own machine thread — captured once, at its
            # first successful spawn (`ensure_center`), so `ensure_thread_sessions` can
            # tell it apart from an ordinary staffed machine thread it should spawn a session for.
            standing_thread_id: nil,
            # Per-thread spawn backoff (mirrors `machine_retry_at`) — thread_id => monotonic
            # retry-at, so a thread whose session keeps failing to spawn isn't retried every render.
            thread_spawn_retry: %{},
            # The two-phase opening-turn inject (see `ensure_thread_sessions`). `opening_text_at`:
            # thread_id => monotonic ms when the turn's TEXT was typed into the fresh `t<id>`
            # window; the Enter follows @opening_submit_delay_ms later so a booting TUI doesn't
            # swallow it. `opening_injected`: thread ids already SUBMITTED (done, never re-touched).
            opening_text_at: %{},
            opening_injected: MapSet.new(),
            # Threads already told "parked: leaf cap reached" — the note posts once, not per render.
            parked_noted: MapSet.new(),
            # Explicit thinking presence: thread_id => %{agent => started_at}. Seeded from the
            # store (reconcile-on-connect), then maintained by the server:presence Bus events.
            thinking: Reads.thinking_snapshot(),
            # Transmitted kitty-graphics ids (design 2026-08-23 §Images) — the sync/2 cache so a
            # placement already on the tty isn't re-transmitted every frame.
            graphics: MapSet.new()
          })

        Process.send_after(self(), :tick, @tick_ms)
        {:ok, state}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's tb_init enables DECCKM (application cursor keys), so arrows arrive as SS3 (ESC O A)
  # instead of CSI — raxol's InputParser only decodes CSI arrows, so under DECCKM :up/:down never
  # fired (only j/k worked). Reset on /dev/tty (the fd termbox drives) so arrows come through as CSI.
  defp normalize_cursor_keys do
    # Best-effort: if /dev/tty can't be written we simply keep termbox's default cursor-key mode.
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state) do
    # Use termbox's re-queried size (refresh_size/tb_resize), not the event's, so state.w/h never
    # exceeds what termbox will actually render at. The tick catches this too as a backstop.
    state = refresh_size(state)
    resize_focused_terminal(state)
    # Every placed image's cell rect is now stale — clear the tty and the sync cache so the next
    # paint re-places (and re-transmits, since the cache is gone) at the new geometry.
    if Console.Graphics.kitty?(), do: IO.write(Console.Graphics.delete_all())
    {:noreply, render(%{state | graphics: MapSet.new()})}
  end

  def handle_cast({:dispatch, %Event{type: :paste, data: %{phase: :start}}}, state) do
    # A paste began: start collecting. A fresh buffer even if one was somehow already open.
    {:noreply, %{state | paste_buffer: Console.PasteBuffer.start()}}
  end

  def handle_cast({:dispatch, %Event{type: :paste, data: %{phase: :end}}}, state) do
    # A paste ended: forward the whole buffer to the center terminal wrapped back in the markers
    # (tmux passes bracketed paste through; pi honors it as one multi-line paste). No center
    # terminal (a non-terminal space) → the paste is dropped, never leaked as stray keys.
    buffer = state.paste_buffer
    state = %{state | paste_buffer: nil}

    if buffer != nil do
      with term when is_pid(term) <- Reads.center_terminal(state) do
        Terminal.feed(term, Console.PasteBuffer.finish(buffer))
      end
    end

    {:noreply, state}
  end

  # While a paste is open, content keys accumulate into the buffer (a newline stays \n, NOT
  # :enter) instead of dispatching to the keymap — so a paste never submits mid-block. Must
  # precede the normal :key clause. Escape force-closes a stuck paste buffer (lost \e[201~) and
  # resumes normal key dispatch, so a dropped paste-end can't wedge the cockpit.
  def handle_cast({:dispatch, %Event{type: :key, data: %{key: :escape}}}, %{paste_buffer: buffer} = state)
      when not is_nil(buffer) do
    {:noreply, %{state | paste_buffer: nil}}
  end

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{paste_buffer: buffer} = state) when not is_nil(buffer) do
    {:noreply, %{state | paste_buffer: Console.PasteBuffer.accumulate(buffer, key)}}
  end

  # An open overlay menu captures navigation keys (Slice 3.5): Esc closes it, j/k/↑↓ move, Enter
  # activates — every other key is swallowed so it can't leak to the frame underneath.
  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{menu: menu} = state) when not is_nil(menu),
    do: overlay_reply(Author.handle_menu_key(key, state), state)

  # The STACK-zoom embedded lazygit (Slice 4): while it's up, every key drives lazygit's PTY — it
  # captures keys like any embedded app (Esc/hjkl/etc. are its own). `Ctrl+Space` (the TERM↔NAV
  # leader, reused) collapses the zoom; quitting lazygit (its `q`) ends the PTY and the tick
  # reconciles the vanished terminal. Precedes the board/menu clauses — a lazygit zoom owns the frame.
  def handle_cast({:dispatch, %Event{type: :key, data: %{key: :space, ctrl: true}}}, %{lazygit: lg} = state)
      when not is_nil(lg), do: {:noreply, render(%{state | lazygit: nil})}

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{lazygit: %{thread_id: id}} = state) do
    with term when is_pid(term) <- Reads.terminal({:lazygit, id}),
         %KeyEvent{} = event <- Console.GhosttyKey.from_event(key) do
      Terminal.send_key(term, event)
    end

    {:noreply, state}
  end

  # A full-screen board (Tickets/Notes) — Esc closes; an ACTIVE input (a new-ticket/note title) takes
  # the keys (input: nil guard fails → falls to the normal dispatch below); else the board key handler
  # drives the kanban cursor + verbs.
  def handle_cast({:dispatch, %Event{type: :key, data: %{key: :escape}}}, %{board: b, input: nil} = state)
      when not is_nil(b), do: {:noreply, render(%{state | board: nil})}

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, %{board: b, input: nil} = state) when not is_nil(b),
    do: overlay_reply(Boards.handle_board_key(key, state), state)

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state) do
    # Any keypress clears a prior flash (a spawn/create result), so it shows until you act again.
    # `center_live?` and `composer_thread_id` are derived per keypress and handed to the keymap so
    # it knows whether to forward to the PTY / which thread `c` targets. They are NOT stored —
    # dropped on the way back; the cockpit keeps only `leader_pending?`.
    # `focus` rides in `state` (persistent); `tlon_layout` is derived per keypress, like the two
    # above, and dropped on the way back — the keymap reads it to navigate, the cockpit never stores it.
    # `author_workspaces` (D2.2): the author face's own workspace list, derived per keypress like
    # `composer_thread_id` — `Console.Workspaces.all/0` is a cached GenServer call (no DB hit), so this
    # keeps `Console.Keymap` a pure reducer with no server call of its own.
    keymap_state =
      %{state | flash: nil}
      # A live PTY only "owns" the keys when it's the shown center — with the thread stack up
      # (center_view :chat, Slice 3) keys drive the stack (j/k/z/Z), never a hidden terminal.
      |> Map.put(:center_live?, state.center_view != :chat and Reads.center_terminal(state) != nil)
      # handle_tlon needs center_view to route center-focus keys to the STACK (not forward to tmux).
      |> Map.put(:center_view, state.center_view)
      # Two-step center: nil = the thread LIST (j/k move · ⏎ open), an id = that CONVERSATION (j/k
      # scroll · esc back). The keymap branches chat keys on it.
      |> Map.put(:opened_thread, state.opened_thread)
      |> Map.put(:composer_thread_id, Reads.composer_thread_id(state))
      |> Map.put(:tlon_layout, Reads.tlon_layout(state))
      |> Map.put(:author_workspaces, Console.Workspaces.all())

    {next, effect} = Keymap.handle(key, keymap_state)

    next =
      reset_scrolls(state, Map.drop(next, [:center_live?, :composer_thread_id, :tlon_layout, :author_workspaces]))

    apply_effect(effect, next)
  end

  # A wheel routes to whatever panel is under the cursor: the center terminal forwards to its PTY
  # or scrolls its scrollback (Console.Terminal.wheel/5), a scrollable list panel advances its offset
  # (clamped to its content height), anything else is ignored. Event coords are 1-based SGR;
  # `Mouse.to_cell/1` normalizes them to the 0-based cells the placement rects use.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: b}}}, state)
      when b in [:wheel_up, :wheel_down] do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}
    dispatch_wheel(Mouse.hit_panel(state.placements, x, y), b, x, y, state)
  end

  # A left click routes to the panel under the cursor and asks it what that row selects — focus a
  # thread, switch a space — then repaints. raxol's `event_translator` gives NO press/release action
  # (mouse data is just `%{x, y, button}`), so a single click surfaces as two identical `:left`
  # events: we act on the first and swallow the second (matched against `last_left`) so nothing
  # double-fires (or re-hits a re-laid-out placement after a space switch). Any other mouse event
  # clears `last_left`, so a repeat click at the same cell still acts. Non-selectable panels return
  # nil → no-op.
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :left}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}

    cond do
      {x, y} == state.last_left ->
        {:noreply, %{state | last_left: nil}}

      # An open overlay menu captures the click: a hit on a menu row runs its action; anywhere else
      # dismisses it (click-away), without falling through to the panel underneath.
      state.menu ->
        handle_menu_click(Mouse.hit_panel(state.placements, x, y), y, %{state | last_left: {x, y}})

      # A full-screen board is view-only for now — any click dismisses it (like Esc).
      state.board ->
        {:noreply, render(%{state | board: nil, last_left: {x, y}})}

      true ->
        dispatch_click(Mouse.hit_panel(state.placements, x, y), x, y, %{state | last_left: {x, y}})
    end
  end

  # A right click on a workspace tile opens its context menu at the cursor; anywhere else dismisses
  # any open menu. Right-click carries no press/release pair to dedup (unlike left).
  def handle_cast({:dispatch, %Event{type: :mouse, data: %{x: sx, y: sy, button: :right}}}, state) do
    {x, y} = {Mouse.to_cell(sx), Mouse.to_cell(sy)}

    if {x, y} == state.last_right do
      {:noreply, %{state | last_right: nil}}
    else
      state = %{state | last_right: {x, y}}

      case context_workspace(Mouse.hit_panel(state.placements, x, y), y) do
        %{id: _} = ws -> {:noreply, render(%{state | menu: Author.workspace_menu(ws, x, y)})}
        nil -> {:noreply, render(%{state | menu: nil})}
      end
    end
  end

  # Any other mouse event (right/middle button, a release/motion that surfaced as a non-`:left`
  # button, wheel handled above) — not acted on, but it CLEARS the click-dedup latch so the next
  # left click at the same cell isn't mistaken for a release.
  def handle_cast({:dispatch, %Event{type: :mouse}}, state), do: {:noreply, %{state | last_left: nil, last_right: nil}}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # A posted message may @-mention a Tlön coworker — wake it by injecting the message as a turn
  # into its tmux window. Routed before the general repaint clause. Best-effort: a window that
  # isn't up yet is skipped (the coworker is never spawned just to deliver a mention).
  @impl true
  def handle_info({:message_posted, row}, state) do
    # First-sight gate (like the tagged-event clause): a message can arrive twice (thread + activity
    # topics, or the mirror re-broadcast), which was doubling every line in the NOW feed. Dedup by id.
    if Reads.fresh?(state, :message_posted, row) do
      Delivery.desktop_notify(:message_posted, row)
      Delivery.mention_notify(row, state)
      state = %{state | seen_events: Reads.cap_seen([Reads.seen_key(:message_posted, row) | state.seen_events])}
      {:noreply, render(Reads.push_activity(state, :message_posted, row))}
    else
      {:noreply, state}
    end
  end

  # The activity-buffer subset of this clause's tags: `Server.Bus` publishes these to the global
  # activity topic (see funes/lib/funes/bus.ex), not just the focused thread's topic — so this
  # is where the Activity feed's `state.activity` gets filled. thread_opened/closed/assigned and
  # session_started/ended ride ONLY their own topics (never activity), so they never reach here
  # via a second path and are left out of the buffer.
  # First-sight gate: a tagged event on the FOCUSED thread is delivered twice (thread topic +
  # activity topic). Dropping the repeat here means desktop_notify/nudge/append each fire once.
  @activity_tags [
    :fact_banked,
    :event_recorded,
    :issue_raised,
    :issue_resolved,
    :question_raised,
    :question_resolved,
    :todo_added,
    :todo_completed
  ]

  def handle_info({tag, row}, state)
      when tag in [
             :fact_banked,
             :event_recorded,
             :issue_raised,
             :issue_resolved,
             :question_raised,
             :question_resolved,
             :todo_added,
             :todo_completed,
             :thread_opened,
             :thread_closed,
             :thread_assigned,
             :session_started,
             :session_ended
           ] do
    if Reads.fresh?(state, tag, row) do
      state = %{state | seen_events: Reads.cap_seen([Reads.seen_key(tag, row) | state.seen_events])}
      Delivery.desktop_notify(tag, row)
      Delivery.nudge_tertius_on_finish(tag, row, state)
      Delivery.teardown_closed_leaf(tag, row, state)
      state = if tag in @activity_tags, do: Reads.push_activity(state, tag, row), else: state
      {:noreply, render(state)}
    else
      {:noreply, state}
    end
  end

  # Workline stage machinery (slice 2): a GATE is the operator's — flash it; an advance is
  # ambient — just repaint so stage chips/counts stay live.
  def handle_info({:workline_gated, thread}, state) do
    Delivery.desktop_notify(:workline_gated, thread)
    {:noreply, render(%{state | flash: "⏸ workline “#{thread.title}” parked at #{thread.stage} — approve #{thread.id}"})}
  end

  # Entering verify dispatches the DETERMINISTIC verifier (scripts/workline-verify.sh):
  # gates run + evidence recorded + advance-on-green, independent of the builder by
  # construction. Fire-and-forget — the script reports through server, not this process.
  def handle_info({:workline_advanced, %{stage: "verify"} = thread}, state) do
    {:ok, _pid} =
      Task.start(fn ->
        System.cmd("mise", ["run", "workline:verify", "--", to_string(thread.id), thread.slug], stderr_to_stdout: true)
      end)

    {:noreply, render(%{state | flash: "▶ verifier dispatched for #{thread.slug}"})}
  end

  def handle_info({:workline_advanced, _thread}, state), do: {:noreply, render(state)}

  # Habit review events refresh the Habits panel (Tlön). No desktop notification — a proposed
  # habit is a quiet queue entry for review, not an interrupt.
  def handle_info({tag, _row}, state) when tag in [:habit_proposed, :habit_approved, :habit_rejected] do
    {:noreply, render(state)}
  end

  # Explicit presence: idempotent updates, so the double delivery on the focused thread
  # (server:presence + its thread topic) just re-writes the same entry.
  def handle_info({:presence_thinking, %{thread_id: tid, agent: agent, started_at: at}}, state) do
    # Server sends a DateTime; cockpit state holds unix seconds (Crew/presence subtract).
    at = Console.Presence.started_s(at)
    thinking = Map.update(state.thinking, tid, %{agent => at}, &Map.put(&1, agent, at))
    {:noreply, render(%{state | thinking: thinking})}
  end

  def handle_info({:presence_idle, %{thread_id: tid, agent: agent}}, state) do
    cleared = state.thinking |> Map.get(tid, %{}) |> Map.delete(agent)
    thinking = if cleared == %{}, do: Map.delete(state.thinking, tid), else: Map.put(state.thinking, tid, cleared)
    {:noreply, render(%{state | thinking: thinking})}
  end

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    # A pending coalesced :render is now redundant (this tick paints); drop the flag so it no-ops.
    state = %{state | render_scheduled?: false}
    # Hot-reload: pick up code recompiled by `console:reload` without a restart (dev loop).
    state = maybe_hot_reload(state)
    # Expire the cached Tlön probes on the probe cadence — render refills them lazily (and only
    # when Tlön is the active space), so the subprocess battery runs at @probe_ms, never per frame.
    state = Reads.maybe_expire_probes(state)
    # Re-sync every tick so a missed SIGWINCH self-corrects: refresh_size re-queries via ioctl,
    # independent of any signal.
    state = refresh_size(state)
    # If the lazygit PTY has exited (its own `q`), Sessions has dropped it — collapse the overlay so
    # it doesn't render `:no_session` over the frame (Slice 4).
    state = reconcile_lazygit(state)
    # Re-fit the center PTY too: a terminal spawned between resizes starts at 80x24 and would
    # otherwise fill only part of the panel. Terminal.resize no-ops when size is unchanged.
    resize_focused_terminal(state)
    {:noreply, render(state)}
  end

  # Rendering per :updated event gave native-latency output but starved input during streaming
  # (the mailbox flooded with terminal events, each doing a full render, key casts queued behind).
  # Coalesce: arm one :render on a short timer; further events until it fires are cheap no-ops.
  def handle_info({Terminal, _pid, _event}, state), do: {:noreply, schedule_render(state)}

  # The coalesced render: clear the armed flag and paint. A :render that arrives with the
  # flag cleared (a tick or key cast already painted and dropped the flag) is a no-op — no
  # double render.
  def handle_info(:render, %{render_scheduled?: false} = state), do: {:noreply, state}
  def handle_info(:render, state), do: {:noreply, render(%{state | render_scheduled?: false})}

  # Trapped exit from the linked input Driver: the cockpit can't take keys anymore, so stop —
  # terminate/2 restores the tty on the way out.
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}

  def handle_info(_msg, state), do: {:noreply, state}

  # Single source of truth for the cockpit's size. termbox only re-learns size in its poll path
  # (which console never calls), so tb_resize/0 (mix.exs defect #3) must sync it first or
  # tb_width()/tb_height() stay frozen at tb_init size.
  defp refresh_size(state) do
    :termbox2_nif.tb_resize()
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  # The tertius band keeps only the last few receipts (the band shows 2; a couple more for scrollback).
  @receipt_cap 6
  # Hot-reload trigger: `mise run console:reload` recompiles (in its own process — no TUI corruption)
  # then touches this file; the cockpit reloads Console.* modules on the next tick. Relative to the
  # cockpit's cwd (modules/console), which the console:reload task shares.
  @reload_trigger ".reload"

  # The thread-stack cards (Slice 3): each machine-thread block → a card. `nil` fold set means
  # "unfold the focused thread" (the default-active-open rule). When `zoomed` names a thread, the
  # stack collapses to just that one card, always unfolded (`Z` — the real zoom). An unfolded card
  # carries the block's messages (already fetched); a folded one drops them.
  # Hot code reload (dev loop) — INTENTIONAL + compile-gated, never automatic on save (which would
  # inevitably swap in mid-edit / broken code). `mise run console:reload` runs `mix compile && touch
  # .reload`: the touch only happens if the compile SUCCEEDS, so the trigger only ever points at
  # good code. The first tick records the baseline; a later mtime change reloads every loaded
  # Console.* module from its fresh .beam — edits land without a cockpit restart, state (folds,
  # focus) persists. A state-SHAPE change still needs `console:run`. Fully guarded.
  defp maybe_hot_reload(%{reload_seen: :unset} = state), do: %{state | reload_seen: trigger_mtime()}

  defp maybe_hot_reload(state) do
    Safe.flash_on_error(state, "reload", fn ->
      case trigger_mtime() do
        m when m != nil and m != state.reload_seen ->
          n = reload_console_modules()
          %{state | reload_seen: m, flash: "↻ reloaded #{n} modules"}

        m ->
          %{state | reload_seen: m}
      end
    end)
  end

  defp trigger_mtime do
    case File.stat(@reload_trigger, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> nil
    end
  end

  defp reload_console_modules do
    :code.all_loaded()
    |> Enum.filter(fn {mod, _} -> mod |> Atom.to_string() |> String.starts_with?("Elixir.Console.") end)
    |> Enum.map(fn {mod, _} ->
      :code.purge(mod)
      :code.load_file(mod)
    end)
    |> length()
  end

  # Entering the PTY, point the center's tmux client at the FOCUSED thread's own lead window (its
  # `t<id>`) so `v` on a thread shows THAT thread's agent, not whatever the standing coworker was on
  # (Andrew: "v takes me to pi"). A root/window-less thread leaves the client where it is.
  defp select_focused_window(%{active_key: key, stack_focus: id}) when Space.workspace?(key) and is_integer(id) do
    Safe.value(
      fn ->
        case Tmux.leaf_tab(Tmux.list_windows(key), id) do
          %{index: idx} -> Tmux.select_window(key, idx)
          _ -> :ok
        end
      end,
      :ok
    )
  end

  defp select_focused_window(_state), do: :ok

  defp dispatch_wheel(nil, _b, _x, _y, state), do: {:noreply, state}

  # The shown terminal (lazygit overlay, else the center): forward to the embedded app if it tracks
  # the mouse, else scroll scrollback.
  defp dispatch_wheel({Panel.Terminal, _data, rect}, b, x, y, state) do
    with term when is_pid(term) <- shown_terminal(state),
         {dir, n} <- Mouse.wheel_of(b) do
      lx = clamp_cell(x - rect.x, rect.w)
      ly = clamp_cell(y - rect.y, rect.h)
      repaint_on_scroll(Terminal.wheel(term, dir, n, lx, ly), state)
    else
      _ -> {:noreply, state}
    end
  end

  # A scrollable list panel: advance its offset, clamped to its content height, and repaint. A
  # non-scrollable panel under the wheel (Spaces, a non-center frame) is a no-op.
  defp dispatch_wheel({panel, data, rect}, b, _x, _y, state),
    do: scroll_wheel(Panel.scrollable?(data), panel, data, rect, b, state)

  defp scroll_wheel(true, panel, data, rect, b, state) do
    {dir, n} = Mouse.wheel_of(b)
    content_h = Panel.content_height(panel, data, rect.w)
    next = Mouse.clamp_offset((state.scrolls[panel] || 0) + Terminal.scroll_delta(dir, n), content_h, rect.h)
    {:noreply, render(%{state | scrolls: Map.put(state.scrolls, panel, next)})}
  end

  defp scroll_wheel(false, _panel, _data, _rect, _b, state), do: {:noreply, state}

  defp clamp_cell(v, extent), do: v |> max(0) |> min(max(extent - 1, 0))

  # The terminal a mouse event on a Panel.Terminal belongs to: while the lazygit overlay is up, ITS
  # PTY owns the frame — never the machine center underneath.
  defp shown_terminal(%{lazygit: %{thread_id: id}}), do: Reads.terminal({:lazygit, id})
  defp shown_terminal(state), do: Reads.center_terminal(state)

  defp repaint_on_scroll(:scrolled, state), do: {:noreply, render(state)}
  defp repaint_on_scroll(:forwarded, state), do: {:noreply, state}

  @doc false
  # The workspace a right click landed on, per the panel under the cursor. The rail carries the
  # workspace rows since the spine left the frame; Panel.Sidebar keeps its door for the drawer.
  # Pure — the right-click `handle_cast` clause turns it into a menu.
  def context_workspace({Panel.Rail, data, rect}, y), do: Panel.Rail.workspace_at(data, rect, y - rect.y)
  def context_workspace({Panel.Sidebar, data, rect}, y), do: Panel.Sidebar.workspace_at(data, rect, y - rect.y)
  def context_workspace(_hit, _y), do: nil

  defp dispatch_click(nil, _x, _y, state), do: {:noreply, state}

  # Clicking the shown terminal: forward to the PTY when the embedded program tracks the mouse
  # (tmux `mouse on` selects; a TUI hit-tests its own regions). The terminal renders edge-to-edge.
  defp dispatch_click({Panel.Terminal, _data, rect}, x, y, state) do
    with term when is_pid(term) <- shown_terminal(state) do
      Terminal.mouse(term, :press, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
    end

    {:noreply, state}
  end

  # Clicking the tertius band focuses its input (Slice 3) — same as Space / `:`. If it's already
  # focused, the click is a no-op so an in-progress command isn't wiped.
  # Clicking the new-thread band focuses its input (2026-09-01) — the persistent create surface. A
  # re-click while it's already focused is a no-op so an in-progress title isn't wiped.
  defp dispatch_click({Panel.NewThread, _data, _rect}, _x, _y, %{input: %{kind: :new_thread}} = state),
    do: {:noreply, state}

  defp dispatch_click({Panel.NewThread, _data, _rect}, _x, _y, state),
    do: {:noreply, render(%{state | input: %{kind: :new_thread, buffer: "", cursor: 0}})}

  defp dispatch_click({Panel.Tertius, _data, _rect}, _x, _y, %{input: %{kind: :orchestrate}} = state),
    do: {:noreply, state}

  defp dispatch_click({Panel.Tertius, _data, _rect}, _x, _y, state),
    do: {:noreply, render(%{state | input: %{kind: :orchestrate, buffer: "", cursor: 0}})}

  defp dispatch_click({panel, data, rect}, _x, y, state), do: apply_pick(Panel.pick(panel, data, rect, y - rect.y), state)

  defp apply_pick(nil, state), do: {:noreply, state}

  # Selecting a thread by click swaps the focused thread (and thus the center's terminal) — no
  # focus flag to clear in the tmux-style model.
  defp apply_pick({:focus_thread, id}, state) do
    next = reset_scrolls(state, %{state | focused_id: id, flash: nil})
    {:noreply, render(next)}
  end

  defp apply_pick({:switch_space, key}, state) do
    next = reset_scrolls(state, %{state | active_key: key, flash: nil})
    {:noreply, render(next)}
  end

  # The spine's `+` tile (Slice 3.4): open the new-workspace input directly — the SAME flow the Orbis
  # author face's `n` opens (template ring on h/l, Enter → {:register_workspace, …}), reused from
  # anywhere so add-a-workspace isn't buried in the god-view.
  defp apply_pick({:new_workspace}, state) do
    input = %{kind: :new_workspace, buffer: "", cursor: 0, template: List.first(WorkspaceTemplates.names())}
    {:noreply, render(%{state | input: input})}
  end

  # The spine's settings cog (Slice 3.4): land on the workspace CONFIG surface — Orbis' author face
  # (D2.1), where workspaces are created/edited/removed (roster, repos, knobs).
  defp apply_pick({:settings}, state) do
    {:noreply, render(%{state | active_key: :orbis, orbis_face: :author})}
  end

  # A picked-but-not-yet-wired surface (the spine's Tickets/Notes tools, Slice 3.5): a transient
  # footer note, honest that it's coming, rather than a dead click.
  defp apply_pick({:flash, message}, state) do
    {:noreply, render(%{state | flash: message})}
  end

  # The spine's Tickets/Notes tools (Slice 3.5): open the full-screen board.
  defp apply_pick({:open_board, kind}, state),
    do: {:noreply, render(%{state | board: kind, board_cursor: {0, 0}, menu: nil})}

  # Click a thread row in the list → open its conversation (two-step center).
  defp apply_pick({:open_thread_view, id}, state), do: apply_effect({:open_thread_view, id}, state)

  # Reset scroll offsets when the context they're relative to changes: a space switch swaps every
  # panel, so all offsets go.
  @doc false
  def reset_scrolls(%{active_key: a}, %{active_key: a2} = next) when a != a2, do: %{next | scrolls: %{}}
  def reset_scrolls(_prev, next), do: next

  defp handle_menu_click({Panel.Menu, data, rect}, y, state),
    do: {:noreply, render(Author.apply_menu(Panel.Menu.pick(data, rect, y - rect.y), state))}

  defp handle_menu_click(_hit, _y, state), do: {:noreply, render(%{state | menu: nil})}

  # An overlay's key handler answers the next state, or `:ignore` for a swallowed key (no repaint).
  defp overlay_reply(:ignore, state), do: {:noreply, state}
  defp overlay_reply(next, _state), do: {:noreply, render(next)}

  # The STACK-zoom embedded lazygit overlay (Slice 4): a full-frame `Panel.Terminal` over the
  # lazygit PTY, painted like a board. `render_state_of` yields the live cell grid or `:no_session`
  # (the tick reconciles a vanished terminal back to `lazygit: nil`).
  defp lazygit_placements(%{lazygit: nil}), do: []

  defp lazygit_placements(%{lazygit: %{thread_id: id, path: path}, w: w, h: h}) do
    rect = %{x: 0, y: 0, w: w, h: max(h - 1, 2)}
    inset = %{x: 1, y: 1, w: max(w - 2, 1), h: max(h - 3, 1)}
    title = "lazygit · #{Path.basename(path)}  ·  ^space to close"

    [
      {Panel.Border, %{focused: true, digit: nil, title: title, tabs: nil, hint: nil}, rect},
      {Panel.Terminal, Reads.render_state_of(Reads.terminal({:lazygit, id})), inset}
    ]
  end

  # `Enter` on a focused STACK pane (or a click) zooms the focused thread's worktree into lazygit.
  # Resolve thread → repo/worktree (`Server.worktree_for_thread`), spawn `lazygit` in a session
  # terminal keyed `{:lazygit, id}`, and mark the overlay. Honest flashes on every miss; a persistent
  # terminal (re-zoom reuses it). Needs `console:run` (new state field) to appear.
  defp open_lazygit(%{lazygit: %{}} = state), do: {:noreply, render(state)}

  defp open_lazygit(%{stack_focus: nil} = state),
    do: {:noreply, render(%{state | flash: "no focused thread — nothing to open lazygit on"})}

  defp open_lazygit(%{stack_focus: id} = state) do
    flashing(state, "lazygit", fn ->
      if Console.Lazygit.available?() do
        case Console.Server.worktree_for_thread(id) do
          {:ok, cwd} -> spawn_lazygit(state, id, cwd)
          {:error, reason} -> {:noreply, render(%{state | flash: "no repo for this thread (#{inspect(reason)})"})}
        end
      else
        {:noreply, render(%{state | flash: "lazygit is not installed"})}
      end
    end)
  end

  defp spawn_lazygit(state, id, cwd) do
    {cmd, args} = Console.Lazygit.command(cwd)
    {cols, rows} = {max(state.w - 2, 1), max(state.h - 3, 1)}

    case safe_session_ensure({:lazygit, id}, cmd: cmd, args: args, cols: cols, rows: rows) do
      {:ok, _pid} -> {:noreply, render(%{state | lazygit: %{thread_id: id, path: cwd}})}
      _ -> {:noreply, render(%{state | flash: "couldn't start lazygit"})}
    end
  end

  # Collapse a lazygit overlay whose terminal has exited (quit from inside) — else it paints
  # `:no_session` over the frame. A no-op while the terminal is live or no overlay is up.
  defp reconcile_lazygit(%{lazygit: %{thread_id: id}} = state) do
    if is_pid(Reads.terminal({:lazygit, id})), do: state, else: %{state | lazygit: nil}
  end

  defp reconcile_lazygit(state), do: state

  # State transitions live in the pure `Console.Keymap`; the Cockpit only runs the side effect it
  # asks for — repaint, quit, or forward a key to the focused terminal.
  defp apply_effect(:repaint, state), do: {:noreply, render(state)}
  defp apply_effect(:none, state), do: {:noreply, state}
  defp apply_effect(:quit, state), do: quit(state)

  # A focused key goes to the focused session's embedded terminal: encode it as a Ghostty.KeyEvent
  # and hand it to the emulator, which writes the right bytes straight to the PTY — one native
  # keystroke, no shell-out. An unmappable key is dropped rather than misdelivered.
  defp apply_effect({:forward, key}, state) do
    with %KeyEvent{} = event <- Console.GhosttyKey.from_event(key),
         term when is_pid(term) <- Reads.center_terminal(state) do
      Terminal.send_key(term, event)
    end

    {:noreply, state}
  end

  defp apply_effect({:create_thread, text}, state) do
    # The typed text is the OPENING MESSAGE, not just a title: post it as the operator so the thread
    # reads as a real chat and its lead has something to answer (the "no messages yet / silent agent"
    # bug). The title is a short slug of it. scope: "machine" so it shows in the stack.
    operator = Console.Config.operator()

    case Channel.open_thread(%{
           title: thread_title(text),
           workspace_id: Space.active_workspace_id(state),
           scope: "machine"
         }) do
      {:ok, thread} ->
        # Post the opening message; do NOT spawn a PTY here. The thread is staffed (the lead
        # invariant), so the render preamble's `ensure_thread_sessions` spawns its LEAD in a window
        # and two-phase-injects this operator message — the proven wake path. `spawn_onto` used to
        # fire here too, spawning a generic "pi" as an invisible per-thread terminal that never got
        # the message (the "agent booted idle" bug) and doubled the real lead's spawn.
        _ = Channel.post(%{thread_id: thread.id, author: operator, body: text})
        {:noreply, render(%{state | focused_id: thread.id, flash: "→ started “#{thread_title(text)}” · waking its lead"})}

      {:error, _changeset} ->
        {:noreply, render(%{state | flash: "couldn't create the thread"})}
    end
  end

  # First-class ticket create (Slice C): file into the active workspace's backlog, flash a receipt.
  defp apply_effect({:file_ticket, title}, state) do
    case Safe.value(
           fn -> Console.Server.Tickets.file(%{workspace_id: Space.active_workspace_id(state), title: title}) end,
           nil
         ) do
      {:ok, t} -> {:noreply, render(%{state | flash: "filed ticket ##{t.id} in backlog"})}
      _ -> {:noreply, render(%{state | flash: "couldn't file the ticket"})}
    end
  end

  # First-class note create (Slice C): a workspace-scoped note, authored by the operator.
  defp apply_effect({:write_note, body}, state) do
    operator = Console.Config.operator()
    attrs = %{body: body, scope: "workspace", scope_id: Space.active_workspace_id(state), author: operator}

    case Safe.value(fn -> Console.Server.Notes.write(attrs) end, nil) do
      {:ok, n} -> {:noreply, render(%{state | flash: "noted ##{n.id}"})}
      _ -> {:noreply, render(%{state | flash: "couldn't save the note"})}
    end
  end

  # The tertius command line (Slice 1): route the typed meta-intent and flash a RECEIPT — a line you
  # talk into with no confirmation is the exact bug this repo opened on 2026-08-30. SAFE verbs
  # (post/note/ticket/query) fire straight; CONSEQUENTIAL ones (open work, approve) ARM the y/n gate
  # (`pending_confirm`) — showing what they WOULD do and firing nothing until the operator says `y`
  # (Console.Keymap → `:confirm_orchestrate`). Slice 3.5.
  defp apply_effect({:orchestrate, text}, state), do: flashing(state, "orchestrate", fn -> orchestrate(text, state) end)

  # `y` on an armed consequential verb (Console.Keymap): fire it now, log the receipt. The arm rode the
  # effect (the keymap already cleared `pending_confirm`), so this is a clean one-shot.
  defp apply_effect({:confirm_orchestrate, %{action: action, ctx: ctx}}, state),
    do: flashing(state, "confirm", fn -> flash_receipt(Console.Orchestrator.confirm(action, ctx), state) end)

  # The `c` verb landed: post the composer's body to the focused thread AS THE OPERATOR (config
  # `:server, :operator`), so a posted message is the human's voice, not an agent's. The Bus
  # announce repaints the chorus live, so the message lands visibly; a failure flashes in the footer.
  defp apply_effect({:post_message, thread_id, body}, state) do
    flashing(state, "post", fn ->
      operator = Console.Config.operator()

      case Channel.post(%{thread_id: thread_id, author: operator, body: body}) do
        {:ok, _message} -> {:noreply, render(%{state | flash: "posted"})}
        {:error, _changeset} -> {:noreply, render(%{state | flash: "couldn't post — is the thread open?"})}
      end
    end)
  end

  # The composer's /status command (reshape slice D): the full HEALTH readout — the panel demoted
  # to a footer line — as a MAIN detail in a Workspace space; Esc closes it like any detail. Orbis has
  # no detail surface (and no health probe), so it degrades to an honest flash.
  defp apply_effect({:show_status, _thread_id}, %{active_key: key} = state) when Space.workspace?(key) do
    state = %{put_in(state.focus.detail?, true) | status_detail: Reads.status_detail_content(state.health)}
    {:noreply, render(state)}
  end

  defp apply_effect({:show_status, _thread_id}, state),
    do: {:noreply, render(%{state | flash: "no health read here — /status works in a workspace"})}

  # The `v` verb landed (reshape slice D): flip the Workspace center between the live PTY and the
  # attached thread's conversation.
  # `v` toggles the center between the thread stack and the live PTY. Entering the PTY, point the
  # center's tmux client at the FOCUSED thread's own lead window (its `t<id>`) — so `v` on a thread
  # shows THAT thread's agent, not whatever the standing coworker was on (Andrew: "v takes me to pi").
  # A root/window-less thread leaves the client where it is (the standing coworker).
  # Open a thread's conversation (two-step center): show ITS messages, scrolled to the latest (a big
  # offset clamps to the bottom at render). Esc closes back to the list.
  defp apply_effect({:open_thread_view, id}, state) when is_integer(id) do
    scrolls = Map.put(state.scrolls, Panel.ThreadStack, 100_000)
    # Opening a thread IS focusing its reply (2026-09-01): seed the persistent `:reply` input so the
    # box is live the instant the conversation shows — no `c` verb. `:close_thread_view` tears it down.
    input = %{kind: :reply, thread_id: id, buffer: "", cursor: 0}
    {:noreply, render(%{state | opened_thread: id, focused_id: id, stack_focus: id, scrolls: scrolls, input: input})}
  end

  defp apply_effect(:open_focused_thread, %{stack_focus: id} = state) when is_integer(id),
    do: apply_effect({:open_thread_view, id}, state)

  defp apply_effect(:open_focused_thread, state), do: {:noreply, state}

  defp apply_effect(:close_thread_view, state),
    do:
      {:noreply, render(%{state | opened_thread: nil, input: nil, scrolls: Map.delete(state.scrolls, Panel.ThreadStack)})}

  # Scroll the open conversation by `n` rows (j/k in conversation mode); clamped at render.
  defp apply_effect({:scroll_conversation, n}, state) do
    cur = Map.get(state.scrolls, Panel.ThreadStack, 0)
    {:noreply, render(%{state | scrolls: Map.put(state.scrolls, Panel.ThreadStack, max(cur + n, 0))})}
  end

  defp apply_effect(:toggle_center_view, state) do
    next = toggle_center_view(state)
    if next.center_view == :terminal, do: select_focused_window(next)
    {:noreply, render(next)}
  end

  # Alt+\ toggles the right SESSION PANE (2026-08-31): show/hide the selected thread's live lead PTY
  # beside the stack. Only meaningful in a workspace chat view; elsewhere it's a harmless flip.
  defp apply_effect(:toggle_session_pane, state), do: {:noreply, render(%{state | session_pane: not state.session_pane})}

  # The `m` verb landed: advance the coworker's driver model one step round the ring and persist
  # it (Console.Config). Honest about scope: the RUNNING coworker keeps its model — the override
  # applies wherever Profiles.fetch flows on the next spawn (console:reset, or kill the pi window).
  defp apply_effect({:cycle_coworker_model, profile_name}, state),
    do:
      flashing(state, "settings write", fn -> {:noreply, render(%{state | flash: Author.cycle_model!(profile_name)})} end)

  # Enter in Tlön nav: on the RAIL, the row under the cursor speaks the click's own verb (open a
  # thread / switch workspace); on STACK, zoom the focused thread's worktree into an embedded
  # lazygit (Slice 4); on a pane with a detail, open it in MAIN (set focus.detail?, which the View
  # renders). `Reads.enter_verb/2` is the pure resolution — `:none` leaves the frame alone, so
  # Enter never arms a detail mode nothing can show (which the next Esc would silently spend).
  defp apply_effect(:tlon_enter, state) do
    # A pane Enter always resolves ITS detail — never a leftover /status readout.
    state = %{state | status_detail: nil}

    case Reads.enter_verb(state, Reads.tlon_layout(state)) do
      {:pick, verb} -> apply_pick(verb, state)
      :lazygit -> open_lazygit(state)
      :detail -> {:noreply, render(put_in(state.focus.detail?, true))}
      :none -> {:noreply, state}
    end
  end

  # Enter on the Orbis survey (D0.2) — the same space-switch a click on the row runs.
  defp apply_effect({:switch_space, key}, state), do: apply_pick({:switch_space, key}, state)

  # Nav v2 (Andrew 2026-08-31): Alt+Shift+N → switch to the Nth workspace (1-based, ordered like the
  # spine); past the end is a no-op.
  defp apply_effect({:switch_workspace_pos, n}, state) do
    case Enum.at(Console.Workspaces.all(), n - 1) do
      %{id: id} -> apply_pick({:switch_space, id}, state)
      _ -> {:noreply, state}
    end
  end

  # Nav v2: Alt+N → select the Nth tmux TAB (window) in the active workspace; past the end is a no-op.
  defp apply_effect({:select_tab, n}, %{active_key: key} = state) when Space.workspace?(key) do
    case Enum.at(Tmux.list_windows(key), n - 1) do
      %{index: idx} -> Tmux.select_window(key, idx)
      _ -> :ok
    end

    {:noreply, state}
  end

  defp apply_effect({:select_tab, _n}, state), do: {:noreply, state}

  # `a` (or Esc from the author face) landed: flip Orbis' face and repaint (D2.1).
  defp apply_effect({:toggle_orbis_face}, state), do: {:noreply, render(Author.toggle_orbis_face(state))}

  # The author face's `n` verb landed: register a workspace from the armed template + typed name.
  defp apply_effect({:register_workspace, template, name}, state),
    do: {:noreply, render(Author.register_workspace!(state, template, name))}

  # `d` on the author face's cursor workspace landed: arm the two-key delete confirm.
  defp apply_effect({:arm_delete, id, name}, state),
    do: {:noreply, render(%{state | pending_delete: id, flash: "press d again to delete #{name}"})}

  # The second `d` (still armed on this id) landed: remove the workspace.
  defp apply_effect({:remove_workspace, id}, state), do: {:noreply, render(Author.remove_workspace!(state, id))}

  # The field editor's h/l rings and paths/roster sub-list add/remove (D2.4 Chunk 2a) landed: apply
  # the attrs map immediately — no draft/commit step, matching Settings' per-change apply.
  defp apply_effect({:edit_workspace, id, attrs}, state), do: {:noreply, render(Author.edit_workspace!(state, id, attrs))}

  # The roster sub-editor's Tab-armed knob landed on Enter/Space (D2.4 Chunk 2b, absorbs Settings):
  # apply it via Console.Config.
  defp apply_effect({:coworker_knob, name, knob}, state),
    do: {:noreply, render(Author.apply_coworker_knob!(state, name, knob))}

  # a/r on Memory's habits section: resolve the selected pending habit from the focus + cached read,
  # act via server, then null the memory cache so the pane reflects the shrunk queue on next render.
  # A no-op (flash only) if the focus isn't on a selectable habit.
  defp apply_effect({:habit_action, action}, state) do
    flashing(state, "habit action", fn ->
      case Reads.selected_habit(state) do
        nil ->
          {:noreply, render(%{state | flash: "no habit selected — Tab to HABITS, j/k to pick"})}

        habit ->
          {verb, result} =
            case action do
              :approve -> {"approved", Console.Server.approve_habit(habit.id)}
              :reject -> {"rejected", Console.Server.reject_habit(habit.id)}
            end

          flash =
            case result do
              {:ok, _} -> "habit #{verb}"
              _ -> "couldn't #{action} habit"
            end

          {:noreply, render(%{state | memory: nil, flash: flash})}
      end
    end)
  end

  # `d` in Tlön nav landed: arm the two-key confirm on the focused pane's selection — a MEMORY
  # pinned fact (forget) or a LEAVES leaf (window + thread). Anywhere else: flash the miss.
  defp apply_effect(:tlon_delete_arm, state) do
    case Reads.tlon_delete_target(state) do
      nil ->
        {:noreply, render(%{state | flash: "nothing deletable under the cursor"})}

      {_kind, _payload, label} = target ->
        {:noreply, render(%{state | tlon_delete: target, flash: "press d again to #{label}"})}
    end
  end

  # Arm the two-key delete for the focused thread CARD (chat stack). The root machine thread is
  # refused by delete_thread itself; here we just resolve the title for the confirm label.
  defp apply_effect(:stack_delete_arm, %{stack_focus: id} = state) when is_integer(id) do
    case Enum.find(state.threads, &(&1.id == id)) do
      %{title: title} ->
        {:noreply,
         render(%{state | tlon_delete: {:thread, id, "delete “#{title}”"}, flash: "press d again to delete “#{title}”"})}

      _ ->
        {:noreply, render(%{state | flash: "no thread focused"})}
    end
  end

  defp apply_effect(:stack_delete_arm, state), do: {:noreply, render(%{state | flash: "no thread focused"})}

  defp apply_effect({:tlon_delete, {:thread, id, _label}}, state) do
    flashing(state, "delete", fn ->
      flash =
        case Console.Server.delete_thread(id) do
          {:ok, thread} -> "deleted “#{thread.title}”"
          {:error, :root_machine_thread} -> "can't delete the root thread"
          {:error, reason} -> "delete refused: #{inspect(reason)}"
        end

      {:noreply, render(%{state | tlon_delete: nil, flash: flash})}
    end)
  end

  # The second `d` (still armed) landed: execute against the ARM-TIME target.
  defp apply_effect({:tlon_delete, {:fact, fact, _label}}, state) do
    flashing(state, "forget", fn ->
      flash =
        case Dossier.forget_fact(fact) do
          {:ok, _} -> "forgot fact ##{fact.id}"
          _ -> "couldn't forget fact ##{fact.id}"
        end

      {:noreply, render(%{state | memory: nil, flash: flash})}
    end)
  end

  # `y` landed: resolve the focused pane's semantic text, OSC-52 it to the host clipboard
  # (through the tty, so it works over SSH), and flash what was taken.
  defp apply_effect(:yank, state) do
    case Reads.yank_text(state) do
      {label, text} ->
        IO.write(Osc.copy(text))
        {:noreply, render(%{state | flash: "yanked #{label}"})}

      nil ->
        {:noreply, render(%{state | flash: "nothing to yank here"})}
    end
  end

  defp orchestrate(text, state) do
    action = Console.Orchestrator.Router.route(text)
    ctx = %{workspace_id: Space.active_workspace_id(state), operator: Console.Config.operator()}

    case {Console.Orchestrator.classify(action), Console.Orchestrator.dispatch(action, ctx)} do
      {:consequential, {:confirm, summary}} ->
        arm = %{action: action, ctx: ctx, summary: summary}
        {:noreply, render(%{state | pending_confirm: arm, flash: "⏸ #{summary}? — y to confirm · n to cancel"})}

      {_class, result} ->
        flash_receipt(result, state)
    end
  end

  # A dispatched/confirmed orchestrator result → a flash + a receipt-log entry (newest-first, capped).
  defp flash_receipt(result, state) do
    flash =
      case result do
        {:ok, receipt} -> receipt
        {:error, msg} -> "✗ #{msg}"
      end

    {:noreply, render(%{state | flash: flash, receipts: Enum.take([flash | state.receipts], @receipt_cap)})}
  end

  # Run a verb that answers `{:noreply, state}`; a raise/exit becomes a footer flash and a repaint —
  # a server hiccup never kills the cockpit.
  defp flashing(state, label, fun) do
    case Safe.call(fun) do
      {:ok, reply} -> reply
      {:error, reason} -> {:noreply, render(Safe.flash_failed(state, label, reason))}
    end
  end

  # Arm one coalesced render if none is armed. The first terminal event in a burst schedules
  # the :render; the rest see the flag set and do nothing — the single :render picks up the
  # latest terminal state, whatever arrived in the ~8ms window.
  defp schedule_render(%{render_scheduled?: true} = state), do: state

  # Sessions is supervised (Console.Supervisor) but the cockpit is NOT — a call against a torn-down
  # registry exits, which would otherwise kill the cockpit. Degrade instead (see `Reads.terminal/1`).

  defp schedule_render(state) do
    Process.send_after(self(), :render, @render_coalesce_ms)
    %{state | render_scheduled?: true}
  end

  # The frame is guarded at two grains. Each server/tmux READ below degrades individually through
  # `Safe.read` — one bad read renders as that panel's quiet state while the rest of the frame
  # stays live — and this wrapper is the backstop for anything left (View.compose, the paint): log
  # and keep the previous frame's state instead of dying.
  defp render(state), do: Safe.logged("render error", state, fn -> do_render(state) end)

  defp do_render(state) do
    # Fill the probe cache (Tlön only) and find-or-spawn the Workspace's roster — both stateful,
    # both rate-limited, both OUT of the per-frame hot path. Each step degrades to the state it
    # was handed, so a tmux/server hiccup skips that step this frame instead of losing the frame.
    state = Safe.read(:probes, state, fn -> Reads.ensure_probes(state) end)
    state = Safe.read(:workspace_roster, state, fn -> Staffing.ensure_workspace_roster(state) end)
    state = Safe.read(:thread_sessions, state, fn -> Staffing.ensure_thread_sessions(state) end)
    state = Safe.read(:session_pane, state, fn -> ensure_session(state) end)

    # The thread-stack blocks (Slice 3): machine-scope threads + their messages — the Tlön cockpit's
    # threads ARE machine-scope, so the stack AND the cockpit's nav (`j`/`k`/`↑`/`↓` via `move/2`)
    # order by this, not the project-scope `chorus`. This is the ONE ordering the cockpit navigates.
    stack_blocks = Safe.read(:stack, [], fn -> Channel.machine_threads(Space.active_workspace_id(state)) end)
    threads = Enum.map(stack_blocks, & &1.thread)
    focused = Reads.focused_thread(threads, state.focused_id)
    state = %{state | threads: threads, focused_id: focused && focused.id}
    state = %{state | stack_focus: Reads.stack_focus(stack_blocks, state.focused_id)}
    state = Safe.read(:resubscribe, state, fn -> resubscribe(state, focused) end)
    reads = Reads.frame(state, stack_blocks, focused)
    # The rail's rows, stashed for the keyboard: j/k's count and Enter's row resolve against the
    # SAME read the frame painted, without a second Board.sidebar/0 round-trip per keypress.
    state = %{state | sidebar: reads.sidebar}

    # A full-screen board covers the layout; the overlay menu paints LAST (on top of everything). Both
    # ride in `placements` so hit_panel can route clicks to them.
    placements =
      View.compose(reads, state.w, state.h) ++
        lazygit_placements(state) ++
        Boards.board_placements(state) ++ Author.menu_placements(state.menu, state.w, state.h)

    placements
    |> Board.compose(state.w, state.h)
    |> Board.paint()

    state = sync_graphics(state, placements)

    %{state | placements: placements}
  end

  # The kitty-graphics pass (design 2026-08-23): after the cell paint, place/refresh every
  # panel-declared image. Non-kitty hosts skip it wholesale (panels showed placeholder runs).
  defp sync_graphics(state, placements) do
    if Console.Graphics.kitty?() do
      wanted = Enum.flat_map(placements, fn {panel, data, rect} -> Panel.images(panel, data, rect) end)
      {io, cache} = Console.Graphics.sync(wanted, state.graphics)
      if IO.iodata_length(io) > 0, do: IO.write(io)
      %{state | graphics: cache}
    else
      state
    end
  end

  # Spawn (or reuse) the selected thread's lead session PTY when the pane is on — a tmux client
  # attached to the thread's lead window in the workspace session (`Console.SessionPane.command/1`).
  # Rate-limited out of the hot path like the other ensure_* preamble steps; a miss just leaves the
  # pane on `:no_session` this frame. LIVE-tunable (the attach shape is the kitty pass).
  defp ensure_session(state) do
    with id when is_integer(id) <- Reads.session_pane_target(state),
         nil <- session_terminal_pid(id),
         %{index: index} <- Tmux.leaf_tab(Tmux.list_windows(Space.active_workspace_id(state)), id) do
      {cmd, args} = Console.SessionPane.command(Space.active_workspace_id(state), index)
      {cols, rows} = Reads.session_pane_dims(state)
      _ = safe_session_ensure({:session, id}, cmd: cmd, args: args, cols: cols, rows: rows)
    end

    state
  end

  defp session_terminal_pid(id) do
    case Reads.terminal({:session, id}) do
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end

  defp safe_session_ensure(key, opts), do: Safe.value(fn -> Sessions.ensure(key, opts) end, :error)

  @doc false
  # The pure flip behind the `v` verb — exposed for TTY-less tests.
  def toggle_center_view(%{center_view: :chat} = state), do: %{state | center_view: :terminal}
  def toggle_center_view(state), do: %{state | center_view: :chat}

  # A thread title from its opening message — first line, trimmed to a glanceable length.
  @doc false
  def thread_title(text) do
    text |> String.split("\n", parts: 2) |> List.first() |> String.trim() |> String.slice(0, 60)
  end

  # Keep the center session's PTY sized to the center region so it reflows with the window. Sized to
  # the EXACT center Terminal rect (Console.View.center_rect — the one layout authority), so the PTY
  # matches what's on screen; the terminal reflows on every window resize.
  defp resize_focused_terminal(state) do
    with term when is_pid(term) <- Reads.center_terminal(state) do
      {cols, rows} = Reads.center_dims(state)
      Terminal.resize(term, cols, rows)
    end
  end

  # Follow the focused thread's Bus topic so its dossier/chat repaint on new activity.
  defp resubscribe(state, focused) do
    id = focused && focused.id

    if id == state.subscribed_thread do
      state
    else
      if state.subscribed_thread, do: Bus.unsubscribe_thread(state.subscribed_thread)
      if id, do: Bus.subscribe_thread(id)
      %{state | subscribed_thread: id}
    end
  end

  # terminate/2 (not the quit path) owns the tty restore, so it runs on a normal quit AND on a
  # crash in any callback — the reason init traps exits. The run loop around this GenServer
  # (relaunch-after-crash, the crash log + issue) is `Console.Cockpit.Recovery`.
  defp quit(state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state), do: teardown(state)

  defp teardown(state) do
    # Best-effort: clear any placed images before the alt screen goes away. Straight to /dev/tty
    # like the Kitty pop below (the io server may already be winding down on a crash), and a
    # failure here must never skip the tty restore (a wedged shell is worse than a stray image).
    Safe.value(fn -> if Console.Graphics.kitty?(), do: File.write("/dev/tty", Console.Graphics.delete_all()) end, :ok)

    # Pop Kitty while still ON the alt screen (the spec gives main and alternate screens
    # INDEPENDENT keyboard-flag stacks, so the pop must land on the screen the push landed on).
    Recovery.pop_modes()

    # Each step in its own try: a wedged Driver stop (it can exceed its 500ms) must never skip
    # tb_shutdown — that skip leaves the shell in alt-screen + mouse-reporting, needing `reset`.
    Safe.value(
      fn -> if is_pid(state.driver) and Process.alive?(state.driver), do: GenServer.stop(state.driver, :normal, 500) end,
      :ok
    )

    Safe.value(fn -> :termbox2_nif.tb_shutdown() end, :ok)

    # Back on the MAIN screen now — final belt-and-braces restore.
    Recovery.restore_host_tty()
  end
end
