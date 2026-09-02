defmodule Console.Cockpit do
  @moduledoc """
  The live loop and the cockpit's one brain (design §8). It *is* the dispatcher: termbox2 paints
  (output-only), `Raxol.Terminal.Driver` feeds it `:key`/`:resize` events as GenServer casts, and
  `Server.Bus` events arrive as plain messages. Every input, resize, Bus event, and tick reloads
  the server reads and repaints. Holds the only shared state — the active space and the focused
  thread (§8) — and caches nothing about tmux past the paint (§5).

  Not supervised at app boot: it grabs the TTY, so it runs only under `mix console.run` in a real
  terminal, never during `mix test`.
  """
  use GenServer

  alias Console.Board
  alias Console.Cockpit.Recovery
  alias Console.Keymap
  alias Console.Mouse
  alias Console.Osc
  alias Console.Panel
  alias Console.Profiles
  alias Console.Reads
  alias Console.Safe
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
  alias Server.Channel
  alias Server.Dossier
  alias Server.Workspaces

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
    do: handle_menu_key(key, state)

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
    do: handle_board_key(key, state)

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

      case Mouse.hit_panel(state.placements, x, y) do
        {Panel.Sidebar, data, rect} ->
          case Panel.Sidebar.workspace_at(data, rect, y - rect.y) do
            %{id: _} = ws -> {:noreply, render(%{state | menu: workspace_menu(ws, x, y)})}
            _ -> {:noreply, render(%{state | menu: nil})}
          end

        _ ->
          {:noreply, render(%{state | menu: nil})}
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
      desktop_notify(:message_posted, row)
      mention_notify(row, state)
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
      desktop_notify(tag, row)
      nudge_tertius_on_finish(tag, row, state)
      teardown_closed_leaf(tag, row, state)
      state = if tag in @activity_tags, do: Reads.push_activity(state, tag, row), else: state
      {:noreply, render(state)}
    else
      {:noreply, state}
    end
  end

  # Workline stage machinery (slice 2): a GATE is the operator's — flash it; an advance is
  # ambient — just repaint so stage chips/counts stay live.
  def handle_info({:workline_gated, thread}, state) do
    desktop_notify(:workline_gated, thread)
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

  # Operator-relevant Bus events become native desktop notifications via an OSC 777 escape —
  # ghostty (Linux and macOS) raises it as a real notification, and only when unfocused (the
  # terminal owns focus policy). Best-effort: a host that ignores OSC 777 ignores the bytes.
  defp desktop_notify(tag, row) do
    with {title, body} <- Console.Notify.for_event(tag, row) do
      _ = File.write("/dev/tty", Console.Notify.osc(title, body))
    end

    :ok
  end

  # A machine LEAF closing nudges the tertius center to refresh the rollup — the "a leaf
  # finished" synthesis trigger. The root closing is not a leaf finish. Best-effort; tertius not up
  # (or not yet captured) = no-op. (record_done-without-close is a future trigger — its Bus event is
  # thread-scoped, so it doesn't reach the cockpit globally the way :thread_closed does.)
  defp nudge_tertius_on_finish(:thread_closed, %{scope: "machine", id: id}, %{standing_thread_id: root} = state)
       when is_integer(root) and is_integer(id) and id != root do
    workspace_id = Space.active_workspace_id(state)

    case tlon_window_index(workspace_id, lead_window_name(workspace_id)) do
      nil ->
        :ok

      index ->
        inject_turn(
          workspace_id,
          index,
          "[tlon] leaf ##{id} finished — run machine_overview and refresh the root rollup."
        )
    end
  end

  defp nudge_tertius_on_finish(_tag, _row, _state), do: :ok

  # A closed leaf's window is torn down (the driver contract's `teardown`, Slice F): the seat
  # frees instead of idling forever — the warm-pool groundwork. Safe against the standing center:
  # `leaf_tab` only matches `@funes_thread`-tagged / legacy `t<id>` windows, never the lead's own
  # window. Can't respawn-loop: the spawn candidates (`Server.staffed_machine_threads`) are OPEN
  # threads only. Best-effort — a vanished window is already what we wanted.
  defp teardown_closed_leaf(:thread_closed, %{scope: "machine", id: id}, state) when is_integer(id) do
    workspace_id = Space.active_workspace_id(state)

    case Tmux.leaf_tab(Tmux.list_windows(workspace_id), id) do
      %{index: index} -> Tmux.kill_window(workspace_id, index)
      _ -> :ok
    end

    :ok
  end

  defp teardown_closed_leaf(_tag, _row, _state), do: :ok

  # @-mention delivery: a posted message naming a coworker (`@tertius-machine` / `@claude-machine`) is
  # injected as a turn into that coworker's tmux window, so a cold pane gets woken instead of silently
  # accumulating an unread thread. Pure routing lives in Console.Mention; this is the edge — best-effort
  # tmux send-keys, never a crash on a missing window.
  defp mention_notify(row, state) do
    lead = thread_lead(row)
    workspace_id = Space.active_workspace_id(state)

    case delivery_target(row, state, lead) do
      :skip ->
        :ok

      {:route, staffed} ->
        for {window, text} <-
              Console.Mention.route(row, [lead: lead, staffed_window: staffed], Space.roster(workspace_id)),
            index = tlon_window_index(workspace_id, window),
            not is_nil(index) do
          inject_turn(workspace_id, index, text)
        end

        :ok
    end
  end

  # Which window a posted message wakes, and whether to wake at all. Every staffed machine thread
  # has its OWN `t<id>` window, so routing depends on which case applies:
  #   * the standing coworker's thread → route globally (`staffed_window: nil`); its lead already
  #     runs in the base `claude`/`pi` window.
  #   * a worker-led staffed thread (claude OR pi — Slice A) that's live AND past its opening turn
  #     → route onto `t<id>`, so replies reach the session working THAT thread — not the standing
  #     coworker (otherwise both the `t2` session and the standing one would answer the same post).
  #   * a worker-led staffed thread mid-spawn / pre-opening → `:skip`: `ensure_thread_sessions`
  #     owns the opening turn (two-phase, race-safe); waking here would double it.
  #   * no staffed lead, or a meta/unknown lead (no leaf window for it) → route globally.
  defp delivery_target(%{thread_id: tid}, state, lead) when is_integer(tid) do
    standing = state.standing_thread_id || Reads.machine_thread_id(Space.active_workspace_id(state))

    cond do
      tid == standing -> {:route, nil}
      is_nil(lead) or not Staffing.leaf_staffed?(lead, Space.active_workspace_id(state)) -> {:route, nil}
      window = staffed_leaf_window(tid, state) -> {:route, window}
      true -> :skip
    end
  end

  defp delivery_target(_row, _state, _lead), do: {:route, nil}

  # The live window NAME of a staffed thread's leaf session, once its opening turn has been
  # submitted — the `staffed_window` redirect target `Console.Mention.route/3` rewrites the lead
  # onto. Resolved via `leaf_tab` (the `@funes_thread` routing map — Slice C); the submitted
  # check reads the window's own `@funes_opening` tag first, so a restarted cockpit (empty
  # `opening_injected`) keeps delivering to already-running leaves instead of `:skip`ping them
  # forever. nil while mid-spawn / pre-opening (→ `:skip`; the spawn pass owns the opening turn).
  defp staffed_leaf_window(tid, state) do
    case Tmux.leaf_tab(Tmux.list_windows(Space.active_workspace_id(state)), tid) do
      %{name: name} = tab ->
        if tab[:opening] == "done" or MapSet.member?(state.opening_injected, tid), do: name

      _ ->
        nil
    end
  end

  # The server handle of the coworker staffed on this message's thread (its lead), or nil.
  # Read in-process (console boots server); never crash the hub if the lookup fails.
  defp thread_lead(%{thread_id: tid}) when not is_nil(tid), do: Safe.value(fn -> Server.thread_lead(tid) end, nil)

  defp thread_lead(_), do: nil

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
    flash_on_error(state, "reload", fn ->
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

  # The active roster's LEAD window name (the center's tab label) for `workspace_id`, or nil (no roster
  # / server down).
  defp lead_window_name(workspace_id) do
    case Space.fetch(workspace_id) do
      %Space{roster: [lead | _]} -> Profiles.roster_entry(lead).name
      _ -> nil
    end
  end

  # The tmux window index for a named coworker window in workspace `workspace_id`, from the live session
  # (nil if not up).
  defp tlon_window_index(workspace_id, name), do: Tmux.window_index(Tmux.list_windows(workspace_id), name)

  # Inject `text` as a submitted turn into window `index`: text, then Enter, in one go. Only safe for
  # a LONG-BOOTED window (the standing coworkers); a freshly-spawned harness needs the two-phase
  # form (`Tmux.send_text` now, `Tmux.submit` on a later render) or the Enter is swallowed.
  defp inject_turn(workspace_id, index, text) do
    Tmux.send_text(workspace_id, index, text)
    Tmux.submit(workspace_id, index)
  end

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
  defp reset_scrolls(%{active_key: a}, %{active_key: a2} = next) when a != a2, do: %{next | scrolls: %{}}
  defp reset_scrolls(_prev, next), do: next

  defp handle_menu_click({Panel.Menu, data, rect}, y, state),
    do: apply_menu(Panel.Menu.pick(data, rect, y - rect.y), state)

  defp handle_menu_click(_hit, _y, state), do: {:noreply, render(%{state | menu: nil})}

  defp handle_menu_key(%{key: :escape}, state), do: {:noreply, render(%{state | menu: nil})}
  defp handle_menu_key(%{char: "j"}, state), do: {:noreply, render(move_menu(state, 1))}
  defp handle_menu_key(%{key: :down}, state), do: {:noreply, render(move_menu(state, 1))}
  defp handle_menu_key(%{char: "k"}, state), do: {:noreply, render(move_menu(state, -1))}
  defp handle_menu_key(%{key: :up}, state), do: {:noreply, render(move_menu(state, -1))}

  defp handle_menu_key(%{key: :enter}, %{menu: %{items: items, cursor: c}} = state),
    do: menu_action(Enum.at(items, c).action, state)

  defp handle_menu_key(_key, state), do: {:noreply, state}

  defp move_menu(%{menu: %{items: items, cursor: c} = menu} = state, delta) do
    n = max(length(items), 1)
    %{state | menu: %{menu | cursor: rem(c + delta + n, n)}}
  end

  # A workspace's context menu, anchored at the click cell.
  defp workspace_menu(ws, x, y) do
    %{
      title: ws.name,
      x: x,
      y: y,
      cursor: 0,
      items: [
        %{label: "Set icon…", action: {:icon_picker, ws}},
        %{label: "Configure", action: {:configure_ws, ws}},
        %{label: "Delete", action: {:delete_ws, ws}, danger: true}
      ]
    }
  end

  # The Set-icon picker: the workspace-icon choices, plus a reset to the position number.
  defp icon_picker_menu(ws, x, y) do
    icons =
      Enum.map(Console.Icons.workspace_icons(), fn name ->
        %{label: to_string(name), action: {:set_icon, ws, to_string(name)}, icon: name}
      end)

    %{title: "icon", x: x, y: y, cursor: 0, items: [%{label: "number", action: {:set_icon, ws, nil}} | icons]}
  end

  defp confirm_delete_menu(ws, x, y) do
    %{
      title: "delete?",
      x: x,
      y: y,
      cursor: 1,
      items: [
        %{label: "Delete #{ws.name}", action: {:confirm_delete, ws}, danger: true},
        %{label: "Cancel", action: :close}
      ]
    }
  end

  defp apply_menu({:menu_pick, action}, state), do: menu_action(action, state)
  defp apply_menu(_none, state), do: {:noreply, render(%{state | menu: nil})}

  defp menu_action(:close, state), do: {:noreply, render(%{state | menu: nil})}

  defp menu_action({:configure_ws, _ws}, state),
    do: {:noreply, render(%{state | menu: nil, active_key: :orbis, orbis_face: :author})}

  defp menu_action({:delete_ws, ws}, %{menu: %{x: x, y: y}} = state),
    do: {:noreply, render(%{state | menu: confirm_delete_menu(ws, x, y)})}

  defp menu_action({:confirm_delete, ws}, state), do: {:noreply, render(%{remove_workspace!(state, ws.id) | menu: nil})}

  defp menu_action({:icon_picker, ws}, %{menu: %{x: x, y: y}} = state),
    do: {:noreply, render(%{state | menu: icon_picker_menu(ws, x, y)})}

  defp menu_action({:set_icon, ws, icon}, state),
    do: {:noreply, render(%{set_workspace_icon(state, ws.id, icon) | menu: nil})}

  defp menu_action(_unknown, state), do: {:noreply, render(%{state | menu: nil})}

  # Merge the chosen icon into the workspace's knobs (nil clears it → back to the number).
  defp set_workspace_icon(state, id, icon) do
    case Enum.find(Workspaces.all(), &(&1.id == id)) do
      %{knobs: knobs} -> edit_workspace!(state, id, %{knobs: put_or_delete_icon(knobs || %{}, icon)})
      _ -> state
    end
  end

  defp put_or_delete_icon(knobs, nil), do: Map.delete(knobs, "icon")
  defp put_or_delete_icon(knobs, icon), do: Map.put(knobs, "icon", icon)

  # The overlay's placements (Border + the Menu content), clamped on screen, painted last (on top).
  defp menu_placements(nil, _w, _h), do: []

  defp menu_placements(%{items: items} = menu, w, h) do
    content_w = max(Panel.Menu.width(menu), String.length(menu[:title] || ""))
    box_w = min(content_w + 4, w)
    box_h = min(length(items) + 2, max(h - 2, 2))
    x = menu.x |> min(w - box_w) |> max(0)
    y = menu.y |> min(h - box_h - 2) |> max(0)
    rect = %{x: x, y: y, w: box_w, h: box_h}
    inset = %{x: x + 2, y: y + 1, w: max(box_w - 4, 1), h: max(box_h - 2, 1)}

    [
      {Panel.Border, %{focused: true, digit: nil, title: menu[:title], tabs: nil, hint: nil}, rect},
      {Panel.Menu, menu, inset}
    ]
  end

  # The full-screen boards (Tickets / Notes, Slice 3.5): the spine tools zoom to a board that
  # covers the frame; Esc closes it. Painted after the layout, before the menu.
  defp board_placements(%{board: nil}), do: []

  defp board_placements(%{board: kind, w: w, h: h} = state) do
    rect = %{x: 0, y: 0, w: w, h: max(h - 1, 2)}
    inset = %{x: 2, y: 1, w: max(w - 4, 1), h: max(h - 3, 1)}
    {panel, data, title} = board_content(kind, state)

    [
      {Panel.Border, %{focused: true, digit: nil, title: "#{title}  ·  esc to close", tabs: nil, hint: nil}, rect},
      {panel, data, inset}
    ]
  end

  defp board_content(:tickets, state) do
    id = board_workspace_id(state)
    tickets = Safe.value(fn -> id && id |> Server.Tickets.in_workspace() |> Enum.map(&ticket_row/1) end, nil) || []

    {Panel.TicketBoard, %{tickets: tickets, cursor: state.board_cursor},
     "TICKETS · h/l·j/k move · p advance · n new · ⏎ promote"}
  end

  defp board_content(:notes, state) do
    id = board_workspace_id(state)
    notes = Safe.value(fn -> id && Server.Notes.for_scope("workspace", id) end, nil) || []
    {Panel.NoteBoard, %{notes: notes}, "NOTES"}
  end

  @ticket_statuses ~w(backlog todo doing done)

  # The Tickets kanban keys (Slice D3): h/l/j/k move the {col,row} cursor, `p` advances the selected
  # ticket's status, `n` files a new one (opens the :new_ticket input), Enter promotes it to a thread.
  # The Notes board (and any other) just closes on Esc — handled by the fall-through.
  defp handle_board_key(%{key: :char, char: "n"}, %{board: :tickets} = state),
    do: {:noreply, render(%{state | input: %{kind: :new_ticket, buffer: "", cursor: 0}})}

  defp handle_board_key(%{key: :char, char: "n"}, %{board: :notes} = state),
    do: {:noreply, render(%{state | input: %{kind: :new_note, buffer: "", cursor: 0}})}

  defp handle_board_key(%{key: :char, char: c}, %{board: :tickets} = state) when c in ~w(h l j k),
    do: {:noreply, render(%{state | board_cursor: move_grid(state.board_cursor, c, ticket_columns(state))})}

  defp handle_board_key(%{key: :char, char: "p"}, %{board: :tickets} = state),
    do: {:noreply, render(advance_selected_ticket(state))}

  defp handle_board_key(%{key: :enter}, %{board: :tickets} = state),
    do: {:noreply, render(promote_selected_ticket(state))}

  defp handle_board_key(_key, state), do: {:noreply, state}

  # The active workspace's tickets grouped into kanban columns (structs — the render maps to rows off
  # the same in_workspace order, so the cursor indexes the same grid).
  defp ticket_columns(state) do
    id = board_workspace_id(state)
    tickets = Safe.value(fn -> id && Server.Tickets.in_workspace(id) end, nil) || []
    Console.Panel.TicketBoard.by_column(tickets)
  end

  defp selected_ticket(%{board_cursor: {col, row}}, cols), do: cols |> Enum.at(col, []) |> Enum.at(row)

  defp move_grid({col, row}, "h", cols), do: clamp_grid(max(col - 1, 0), row, cols)
  defp move_grid({col, row}, "l", cols), do: clamp_grid(min(col + 1, length(cols) - 1), row, cols)
  defp move_grid({col, row}, "j", cols), do: clamp_grid(col, row + 1, cols)
  defp move_grid({col, row}, "k", cols), do: clamp_grid(col, max(row - 1, 0), cols)

  defp clamp_grid(col, row, cols) do
    len = length(Enum.at(cols, col, []))
    {col, row |> max(0) |> min(max(len - 1, 0))}
  end

  defp advance_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{status: status} = ticket ->
        next = Enum.at(@ticket_statuses, min(Enum.find_index(@ticket_statuses, &(&1 == status)) + 1, 3), status)
        _ = Safe.value(fn -> Server.Tickets.update(ticket, %{status: next}) end, nil)
        %{state | flash: "ticket ##{ticket.id} → #{next}"}

      _ ->
        state
    end
  end

  defp promote_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{id: id, title: title} = ticket ->
        with {:ok, thread} <-
               Channel.open_thread(%{title: title, workspace_id: Space.active_workspace_id(state), scope: "machine"}),
             {:ok, _} <- Safe.value(fn -> Server.Tickets.promote(ticket, thread.id) end, nil) do
          _ = Staffing.spawn_onto(thread.id, Reads.center_dims(state))
          %{state | board: nil, focused_id: thread.id, flash: "promoted ticket ##{id} → thread"}
        else
          _ -> %{state | flash: "couldn't promote the ticket"}
        end

      _ ->
        state
    end
  end

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
        case Server.worktree_for_thread(id) do
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

  defp ticket_row(t), do: %{id: t.id, title: t.title, status: t.status, priority: t.priority, assignee: t.assignee}

  # The workspace whose tickets/notes the board shows: the active one, or the default (Orbis falls
  # back to the first workspace via active_workspace_id/1).
  defp board_workspace_id(state), do: Space.active_workspace_id(state)

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
    case Safe.value(fn -> Server.Tickets.file(%{workspace_id: Space.active_workspace_id(state), title: title}) end, nil) do
      {:ok, t} -> {:noreply, render(%{state | flash: "filed ticket ##{t.id} in backlog"})}
      _ -> {:noreply, render(%{state | flash: "couldn't file the ticket"})}
    end
  end

  # First-class note create (Slice C): a workspace-scoped note, authored by the operator.
  defp apply_effect({:write_note, body}, state) do
    operator = Console.Config.operator()
    attrs = %{body: body, scope: "workspace", scope_id: Space.active_workspace_id(state), author: operator}

    case Safe.value(fn -> Server.Notes.write(attrs) end, nil) do
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
    do: flashing(state, "settings write", fn -> {:noreply, render(%{state | flash: cycle_model!(profile_name)})} end)

  # Enter in Tlön nav: on the Sidebar, switch to the space under the cursor; on STACK, zoom the
  # focused thread's worktree into an embedded lazygit (Slice 4); on any other pane, open its
  # selection's detail in MAIN (set focus.detail?, which the View renders).
  defp apply_effect(:tlon_enter, state) do
    # A pane Enter always resolves ITS detail — never a leftover /status readout.
    state = %{state | status_detail: nil}
    layout = Reads.tlon_layout(state)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Sidebar -> apply_pick({:switch_space, Reads.space_at_cursor(state, layout)}, state)
      Panel.Stack -> open_lazygit(state)
      _ -> {:noreply, render(put_in(state.focus.detail?, true))}
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
  defp apply_effect({:toggle_orbis_face}, state), do: {:noreply, render(toggle_orbis_face(state))}

  # The author face's `n` verb landed: register a workspace from the armed template + typed name.
  defp apply_effect({:register_workspace, template, name}, state),
    do: {:noreply, render(register_workspace!(state, template, name))}

  # `d` on the author face's cursor workspace landed: arm the two-key delete confirm.
  defp apply_effect({:arm_delete, id, name}, state),
    do: {:noreply, render(%{state | pending_delete: id, flash: "press d again to delete #{name}"})}

  # The second `d` (still armed on this id) landed: remove the workspace.
  defp apply_effect({:remove_workspace, id}, state), do: {:noreply, render(remove_workspace!(state, id))}

  # The field editor's h/l rings and paths/roster sub-list add/remove (D2.4 Chunk 2a) landed: apply
  # the attrs map immediately — no draft/commit step, matching Settings' per-change apply.
  defp apply_effect({:edit_workspace, id, attrs}, state), do: {:noreply, render(edit_workspace!(state, id, attrs))}

  # The roster sub-editor's Tab-armed knob landed on Enter/Space (D2.4 Chunk 2b, absorbs Settings):
  # apply it via Console.Config.
  defp apply_effect({:coworker_knob, name, knob}, state), do: {:noreply, render(apply_coworker_knob!(state, name, knob))}

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
              :approve -> {"approved", Server.approve_habit(habit.id)}
              :reject -> {"rejected", Server.reject_habit(habit.id)}
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
        case Server.delete_thread(id) do
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
      {:error, reason} -> {:noreply, render(flash_failed(state, label, reason))}
    end
  end

  # The state-returning twin: `fun` yields the next state, or the failure flashes on the old one.
  defp flash_on_error(state, label, fun) do
    case Safe.call(fun) do
      {:ok, next} -> next
      {:error, reason} -> flash_failed(state, label, reason)
    end
  end

  defp flash_failed(state, label, reason), do: %{state | flash: "#{label} failed: #{Safe.describe(reason)}"}

  @doc false
  # The pure flip behind Orbis' `a`/Esc (D2.1) — public + exposed so it's
  # testable without a live GenServer.
  def toggle_orbis_face(%{orbis_face: :author} = state), do: %{state | orbis_face: :survey}
  def toggle_orbis_face(state), do: %{state | orbis_face: :author}

  @doc false
  # Register a workspace from `template` + the operator-typed `name` (D2.3's `n` verb). `{:ok, _}`
  # clears the input and flashes; `{:error, changeset}` (a blank OR duplicate name — both are the
  # server changeset's job, not re-validated here) flashes the reason and REOPENS the input with
  # what was typed, so a rejected name can be edited and resubmitted rather than retyped from
  # scratch. Wrapped like `create_thread`/`post_message` — a server hiccup flashes, never crashes
  # the cockpit.
  def register_workspace!(state, template, name) do
    flash_on_error(state, "create", fn ->
      case Workspaces.register(WorkspaceTemplates.new_workspace_attrs(template, name)) do
        {:ok, workspace} ->
          %{state | input: nil, flash: "created #{workspace.name}"}

        {:error, changeset} ->
          %{
            state
            | input: %{kind: :new_workspace, buffer: name, cursor: String.length(name), template: template},
              flash: "couldn't create “#{name}” — #{changeset_error(changeset)}"
          }
      end
    end)
  end

  @doc false
  # Remove workspace `id` (D2.5's second `d`). Guards against stranding the cockpit on a deleted
  # active workspace (falls back to `:orbis`) and clamps `author_cursor` to the shrunk list. A missing
  # workspace (already gone) or a server hiccup flashes, never crashes.
  def remove_workspace!(state, id) do
    flash_on_error(state, "delete", fn ->
      case Workspaces.get(id) do
        nil ->
          %{state | flash: "workspace ##{id} already gone"}

        workspace ->
          case Workspaces.remove(workspace) do
            {:ok, _} ->
              state
              |> Map.put(:active_key, if(state.active_key == id, do: :orbis, else: state.active_key))
              |> Map.put(:author_cursor, clamp_author_cursor(state.author_cursor))
              |> Map.put(:flash, "deleted #{workspace.name}")

            {:error, :last_workspace} ->
              %{state | flash: "couldn't delete #{workspace.name} — the last workspace; threads must have a home"}

            {:error, changeset} ->
              %{state | flash: "couldn't delete #{workspace.name} — #{changeset_error(changeset)}"}
          end
      end
    end)
  end

  # Re-clamp the author cursor against the POST-delete count (one fewer row) — same edge-clamp
  # discipline as the keymap's move_author_cursor, applied here since a delete can shrink the list
  # out from under a cursor sitting on (or past) the new last row.
  defp clamp_author_cursor(cursor), do: max(min(cursor, max(length(Workspaces.all()) - 1, 0)), 0)

  @doc false
  # Apply one field edit (D2.4 Chunk 2a: the editor's type/scope rings, and the paths/roster
  # sub-list's add/remove) immediately — no draft/commit step, mirroring how Settings applies each
  # change on the spot. `name` is immutable (`Workspace.edit_changeset` drops it — see server/workspace.ex);
  # nothing here special-cases it. Same missing/error/rescue shape as `register_workspace!`/
  # `remove_workspace!`. On success, re-clamps `author_edit.sub` against the POST-edit paths/roster
  # length (a removal can strand `sub` past the shrunk list, same reasoning as
  # `clamp_author_cursor/1` above).
  def edit_workspace!(state, id, attrs) do
    flash_on_error(state, "edit", fn ->
      case Workspaces.get(id) do
        nil ->
          %{state | flash: "workspace ##{id} already gone"}

        workspace ->
          case Workspaces.edit(workspace, attrs) do
            {:ok, updated} -> reclamp_author_edit_sub(%{state | flash: "updated #{updated.name}"})
            {:error, changeset} -> %{state | flash: "couldn't update #{workspace.name} — #{changeset_error(changeset)}"}
          end
      end
    end)
  end

  # Only reachable when `author_edit` is actually mid-edit on a paths/roster sub-list (field 2/3) —
  # elsewhere (the type/scope rings, or no editor open) this is a no-op via the fallback clause.
  defp reclamp_author_edit_sub(%{author_edit: %{id: id, field: field} = edit} = state) when field in [2, 3] do
    case Workspaces.get(id) do
      nil ->
        state

      workspace ->
        len = workspace |> Map.get(sub_list_field(field)) |> length()
        %{state | author_edit: %{edit | sub: edit.sub |> min(max(len - 1, 0)) |> max(0)}}
    end
  end

  defp reclamp_author_edit_sub(state), do: state

  defp sub_list_field(2), do: :paths
  defp sub_list_field(3), do: :roster

  @doc false
  # The roster sub-editor's Tab+Enter/Space knob (D2.4 Chunk 2b — absorbs the Settings modal):
  # cycle the sub-selected coworker's model ring, or flip its yolo policy, writing Console.Config
  # (file-backed, applies on the coworker's NEXT SPAWN — same honest scope as the `m` verb/old
  # Settings). Looks the roster entry up off the LIVE workspace (Workspaces.get, like edit_workspace!) rather
  # than trust the effect's bare name, so the entry's archetype (the model ring's default-fallback
  # source) is available.
  def apply_coworker_knob!(state, name, knob) do
    flash_on_error(state, "settings write", fn ->
      case roster_entry_for(state, name) do
        nil -> %{state | flash: "#{name}: roster entry not found"}
        entry -> %{state | flash: apply_knob(entry, knob)}
      end
    end)
  end

  defp roster_entry_for(%{author_edit: %{id: id}}, name) do
    case Workspaces.get(id) do
      nil -> nil
      workspace -> Enum.find(workspace.roster || [], &(&1["name"] == name))
    end
  end

  defp roster_entry_for(_state, _name), do: nil

  defp apply_knob(entry, :model) do
    norm = Profiles.roster_entry(entry)
    next = Profiles.next_model(Profiles.instantiate(norm).model)
    Console.Config.put_coworker_model(norm.name, next)
    "#{norm.name} driver → #{next.provider}/#{next.model} — applies on next spawn (console:reset)"
  end

  defp apply_knob(entry, :yolo) do
    name = entry["name"]
    next = Console.Config.coworker_yolo(name) != true
    Console.Config.put_coworker_yolo(name, next)
    policy = if next, do: "yolo (auto-approve)", else: "ask"
    "#{name} permissions → #{policy} — applies on next spawn (console:reset)"
  end

  # A short "field message, message" sentence from an Ecto changeset — surfaces e.g. a duplicate
  # name's UNIQUE(name) violation ("name has already been taken") without a full inspect dump.
  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  # Arm one coalesced render if none is armed. The first terminal event in a burst schedules
  # the :render; the rest see the flag set and do nothing — the single :render picks up the
  # latest terminal state, whatever arrived in the ~8ms window.
  defp schedule_render(%{render_scheduled?: true} = state), do: state

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

    # A full-screen board covers the layout; the overlay menu paints LAST (on top of everything). Both
    # ride in `placements` so hit_panel can route clicks to them.
    placements =
      View.compose(reads, state.w, state.h) ++
        lazygit_placements(state) ++
        board_placements(state) ++ menu_placements(state.menu, state.w, state.h)

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

  # Sessions is supervised (Console.Supervisor) but the cockpit is NOT — a call against a torn-down
  # registry exits, which would otherwise kill the cockpit. Degrade instead (see `Reads.terminal/1`).

  defp safe_session_ensure(key, opts), do: Safe.value(fn -> Sessions.ensure(key, opts) end, :error)

  @doc false
  # The pure flip behind the `v` verb — exposed for TTY-less tests.
  def toggle_center_view(%{center_view: :chat} = state), do: %{state | center_view: :terminal}
  def toggle_center_view(state), do: %{state | center_view: :chat}

  # Advance a coworker's driver one step round the ring and persist it; returns the flash string.
  defp cycle_model!(profile_name) do
    current = Profiles.fetch(profile_name)
    next = Profiles.next_model(current && current.model)
    Console.Config.put_coworker_model(profile_name, next)
    "coworker driver → #{next.provider}/#{next.model} — applies on next spawn (console:reset)"
  end

  # A thread title from its opening message — first line, trimmed to a glanceable length.
  defp thread_title(text) do
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
