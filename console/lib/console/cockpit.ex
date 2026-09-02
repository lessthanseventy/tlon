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
  alias Console.Harness
  alias Console.Keymap
  alias Console.LeafWindow
  alias Console.Mouse
  alias Console.Osc
  alias Console.Panel
  alias Console.Profile
  alias Console.Profiles
  alias Console.Sessions
  alias Console.Space
  alias Console.Terminal
  alias Console.Tlon.Focus
  alias Console.View
  alias Console.WorkspaceTemplates
  alias Ghostty.KeyEvent
  alias Raxol.Core.Events.Event
  alias Server.Bus
  alias Server.Channel
  alias Server.Dossier
  alias Server.MCP.Spawn
  alias Server.Staff
  alias Server.Workspaces

  # `Space.workspace?/1` is a `defguard` (usable in clause-head `when`s), which requires the module,
  # not just an alias.
  require Space

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

  # The Workspace's cast is roster-driven (`ensure_workspace_roster/1`, C2.3): head = the center (embedded
  # terminal, `new-session`), tail = tmux windows (`new-window`), harness-dispatched. Server handle =
  # `"<name>-machine"`, tmux window = `"<name>"` (`roster_entry/1`). No more hardcoded
  # tertius/hronir/claude-machine identity — the seed roster (surveyor "tertius", builder "hronir")
  # reproduces the old Borges cast (**general** console · **hronir** builder · **tertius**
  # orchestrator) as DATA, not constants.

  # tmux is a first-class stack citizen here: each Workspace's center is a real `tmux attach`, so the
  # workspace gets mouse, windows, and copy-mode, and it SURVIVES console restarts. Session/socket are
  # id-derived (workspace_session/1, workspace_socket/1, near tlon_tmux/2) — not name-derived — so a workspace
  # rename can't orphan the running session and two workspaces never collide.

  # Tlön probe cadence: the Stack/Health reads fork subprocesses (git ×~6, nix-env, df, tmux)
  # and open a TCP probe — far too heavy to run per render (a streaming terminal coalesces to
  # ~125 renders/sec, and one nix-env alone exceeds the whole 8ms window; renders serialized
  # and starved input). Probes are CACHED in cockpit state and refreshed at most this often,
  # on the tick; every other render (keys, Bus events, terminal frames) reads the cache.
  @probe_ms 2_000

  # A failed machine-coworker spawn must not retry on every render (materialise + tmux
  # new-session per frame = a spawn storm whenever the coworker can't start). Back off.
  @machine_spawn_backoff_ms 5_000

  # Same backoff, per-thread: a staffed machine thread whose `tmux new-window`/`Spawn.join`
  # keeps failing (server hiccup, a stale agent) must not retry on every render either — see
  # `ensure_thread_sessions`.
  @thread_spawn_backoff_ms 5_000

  # How long to let a freshly-spawned per-thread window settle between typing its opening turn and
  # sending Enter (the two-phase inject). A just-booted Claude Code TUI takes the text but
  # swallows an Enter that arrives in the same burst; a beat later it submits cleanly. Tunable —
  # bump it if the first turn still lands typed-but-unsent.
  @opening_submit_delay_ms 1_200

  # Crash recovery (see run/0): relaunch the cockpit in place after a crash, but give up after
  # @resurrect_max_fails crashes in a row so a persistent bad state can't spin the terminal. A run
  # that survived @resurrect_healthy_ms is treated as healthy — its next crash starts the count over.
  @resurrect_max_fails 3
  @resurrect_healthy_ms 5_000

  # The server identity the Tlön pi needs to wire its MCP client (`${TLON_MCP_URL}` in the profile's
  # mcp.json + the bearer minted for TLON_THREAD/TLON_AUTHOR). Carried into the tmux SESSION env so
  # it survives a respawn — see funes_identity_flags/0.
  @funes_identity_env ~w(TLON_MCP_URL TLON_THREAD TLON_AUTHOR TLON_DB)

  # The empty Stack shape non-Tlön spaces (and a not-yet-probed Tlön) render.
  @empty_stack %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []}

  # Kitty keyboard protocol: push flags + set disambiguate (CSI > 1 u) at init, pop (CSI < u)
  # at teardown. See the init comment for the full shifted-key round-trip.
  @kitty_enable "\e[>1u"
  @kitty_disable "\e[<u"

  # Bracketed paste: enable (\e[?2004h) at init so ghostty wraps a paste in \e[200~…\e[201~,
  # disable (\e[?2004l) at teardown. Without it a paste reaches raxol's InputParser one char at a
  # time and every newline submits; with it the cockpit's paste buffer forwards the whole block.
  @paste_enable "\e[?2004h"
  @paste_disable "\e[?2004l"

  # Button-motion mouse tracking (\e[?1002h): report mouse MOTION while a button is held, not just
  # press/release. The raxol Driver enables only 1000 (button) + 1006 (SGR); without 1002 ghostty
  # sends nothing during a drag, so a Tlön text selection only highlights on mouseup. Enabled here
  # (additive to the Driver's modes, written after it starts); teardown's reset already clears 1002.
  @mouse_motion_enable "\e[?1002h"

  @doc "Start the cockpit and block until the operator quits — the entry point `mix console.run` calls."
  @spec run() :: :ok
  def run, do: run(0)

  # `strikes` = consecutive rapid crashes so far. The cockpit is an unlinked, monitored GenServer —
  # its crash surfaces here as a clean DOWN (a linked exit would kill this task before it restored
  # the terminal). server (Repo/Bus) and the session terminals are supervised and keep running, so a
  # crash relaunches a FRESH cockpit in place — a reconnect, not a cold boot — unless it's looping.
  defp run(strikes) do
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        started = System.monotonic_time(:millisecond)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            restore_host_tty()
            # Capture a crashed exit — the alt-screen otherwise swallows it silently. (No-op on a
            # clean quit, so a normal `q` never spams the log.)
            log_crash(reason)
            act_on(resurrect_decision(reason, strikes, System.monotonic_time(:millisecond) - started, stdio_alive?()))
        end

      {:error, {:tb_init_failed, code}} ->
        note("console needs a real terminal (tb_init returned #{code}) — run this in ghostty.")
        :ok

      {:error, reason} ->
        note("console failed to start: #{inspect(reason)}")
        :ok
    end
  end

  @doc false
  # The recovery decision after a cockpit goes DOWN. Pure so it's unit-tested without a TTY:
  #   :quit              — a clean operator quit (:normal / :shutdown), end the session.
  #   {:resurrect, n}    — a crash; relaunch, now on strike n.
  #   {:stop, n}         — the nth crash in a row hit the ceiling; stay down.
  #   :dead_io           — a crash, but :standard_io died with it; a relaunch would raise on
  #                        init's alt-screen writes ("console failed to start"), so stay down.
  # `crash_report/1` is the clean-vs-crash oracle (nil = normal/shutdown). A run that lasted at
  # least @resurrect_healthy_ms resets the strike count, so an isolated crash always heals.
  def resurrect_decision(reason, prev_strikes, alive_ms, io_alive? \\ true) do
    cond do
      is_nil(crash_report(reason)) ->
        :quit

      not io_alive? ->
        :dead_io

      true ->
        strikes = if alive_ms >= @resurrect_healthy_ms, do: 1, else: prev_strikes + 1
        if strikes >= @resurrect_max_fails, do: {:stop, strikes}, else: {:resurrect, strikes}
    end
  end

  # :io requests to a dead device return {:error, :terminated} instead of raising — the probe a
  # resurrect runs before writing anything to :standard_io again.
  defp stdio_alive?, do: match?(opts when is_list(opts), :io.getopts(:standard_io))

  # stderr can be as dead as stdio after a host-side teardown — a status line is never worth a
  # second crash in the recovery path.
  defp note(msg) do
    IO.puts(:stderr, msg)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp act_on(:quit), do: :ok

  defp act_on(:dead_io) do
    Console.CrashLog.append("resurrect skipped", "stdio died with the cockpit — staying down")
    note("console crashed and its terminal is gone — staying down. Trace: #{Console.CrashLog.path()}")
    :ok
  end

  defp act_on({:stop, n}) do
    note("console crashed #{n}× in a row — staying down. Trace: #{Console.CrashLog.path()}")
    :ok
  end

  defp act_on({:resurrect, n}) do
    note("console crashed — recovering in place… (#{n}/#{@resurrect_max_fails})")
    run(n)
  end

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
            activity: seed_activity(),
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
            thinking: thinking_snapshot(),
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
      with term when is_pid(term) <- center_terminal(state) do
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
    with term when is_pid(term) <- safe_terminal({:lazygit, id}),
         %KeyEvent{} = event <- ghostty_key(key) do
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
      |> Map.put(:center_live?, state.center_view != :chat and center_terminal(state) != nil)
      # handle_tlon needs center_view to route center-focus keys to the STACK (not forward to tmux).
      |> Map.put(:center_view, state.center_view)
      # Two-step center: nil = the thread LIST (j/k move · ⏎ open), an id = that CONVERSATION (j/k
      # scroll · esc back). The keymap branches chat keys on it.
      |> Map.put(:opened_thread, state.opened_thread)
      |> Map.put(:composer_thread_id, composer_thread_id(state))
      |> Map.put(:tlon_layout, tlon_layout(state))
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
    if fresh?(state, :message_posted, row) do
      desktop_notify(:message_posted, row)
      mention_notify(row, state)
      state = %{state | seen_events: cap_seen([seen_key(:message_posted, row) | state.seen_events])}
      {:noreply, render(push_activity(state, :message_posted, row))}
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
    if fresh?(state, tag, row) do
      state = %{state | seen_events: cap_seen([seen_key(tag, row) | state.seen_events])}
      desktop_notify(tag, row)
      nudge_tertius_on_finish(tag, row, state)
      teardown_closed_leaf(tag, row, state)
      state = if tag in @activity_tags, do: push_activity(state, tag, row), else: state
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
    state = maybe_expire_probes(state)
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

  @activity_cap 50
  # The tertius band keeps only the last few receipts (the band shows 2; a couple more for scrollback).
  @receipt_cap 6
  # Hot-reload trigger: `mise run console:reload` recompiles (in its own process — no TUI corruption)
  # then touches this file; the cockpit reloads Console.* modules on the next tick. Relative to the
  # cockpit's cwd (modules/console), which the console:reload task shares.
  @reload_trigger ".reload"
  @seen_cap 100

  # Prepend `{tag, row}` to the activity buffer (newest-first, capped at @activity_cap). Tagged
  # events are already deduped by the `fresh?/3` first-sight gate in handle_info; messages reach
  # the cockpit once (only via the activity topic, since init dropped subscribe_messages).
  defp push_activity(state, tag, row) do
    %{state | activity: Enum.take([{tag, row} | state.activity], @activity_cap)}
  end

  # The one-shot backfill behind `activity: []`'s replacement — the durable feed at cockpit start,
  # guarded so a not-yet-up server (init can race the server boot) just yields an empty ring rather
  # than crashing the cockpit. Scoped to the active workspace at render by `scope_activity/2`.
  defp seed_activity, do: Board.safe_read(:activity_seed, [], fn -> Server.Board.recent_activity(@activity_cap) end)

  # First-sight test for a tagged event: true unless its key is already in the recently-seen set.
  # The key is `{tag, row.id}` (a durable row always has an id, so the two topic deliveries share
  # it); a row with no id falls back to the whole `{tag, row}` term.
  defp fresh?(state, tag, row), do: seen_key(tag, row) not in state.seen_events

  defp seen_key(tag, %{id: id}) when not is_nil(id), do: {tag, id}
  defp seen_key(tag, row), do: {tag, row}

  defp cap_seen(keys), do: Enum.take(keys, @seen_cap)

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
    workspace_id = active_workspace_id(state)

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
    workspace_id = active_workspace_id(state)

    case leaf_tab(tlon_tabs(workspace_id), id) do
      %{index: index} -> tlon_run(workspace_id, ["kill-window", "-t", "#{workspace_session(workspace_id)}:#{index}"])
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
    workspace_id = active_workspace_id(state)

    case delivery_target(row, state, lead) do
      :skip ->
        :ok

      {:route, staffed} ->
        for {window, text} <-
              Console.Mention.route(row, [lead: lead, staffed_window: staffed], active_roster(workspace_id)),
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
    standing = state.standing_thread_id || machine_thread_id(active_workspace_id(state))

    cond do
      tid == standing -> {:route, nil}
      is_nil(lead) or not leaf_staffed?(lead, active_workspace_id(state)) -> {:route, nil}
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
    case leaf_tab(tlon_tabs(active_workspace_id(state)), tid) do
      %{name: name} = tab ->
        if tab[:opening] == "done" or MapSet.member?(state.opening_injected, tid), do: name

      _ ->
        nil
    end
  end

  # The server handle of the coworker staffed on this message's thread (its lead), or nil.
  # Read in-process (console boots server); never crash the hub if the lookup fails.
  defp thread_lead(%{thread_id: tid}) when not is_nil(tid) do
    Server.thread_lead(tid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp thread_lead(_), do: nil

  # The tmux target workspace id for a call site that only has `state` (not a `Space.workspace?`-guarded
  # `active_key`) in scope — a background Bus handler, or a click that landed on a Workspace-only panel.
  # `state.active_key` when it names a Workspace, else the server-down/no-active-workspace fallback
  # (`Space.first_workspace/0`) — nil when no workspace exists at all; `tlon_run/2` no-ops on nil.
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
    case trigger_mtime() do
      m when m != nil and m != state.reload_seen ->
        n = reload_console_modules()
        %{state | reload_seen: m, flash: "↻ reloaded #{n} modules"}

      m ->
        %{state | reload_seen: m}
    end
  rescue
    e -> %{state | flash: "reload failed: #{Exception.message(e)}"}
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

  # The stack's own focus: the cockpit's focused thread if it's IN the stack, else the first card —
  # so a card is always active/unfolded even when the cockpit's focus tracks a non-stack thread.
  defp stack_focus(blocks, focused_id) do
    ids = Enum.map(blocks, & &1.thread.id)
    if focused_id in ids, do: focused_id, else: List.first(ids)
  end

  # The two-step card set: every thread as a list row; only the `opened` one carries its messages
  # (the conversation view). `active?` is the list cursor; `typing` the thinking chip.
  defp thread_cards(blocks, focus, opened, thinking) do
    Enum.map(blocks, fn %{thread: t, messages: messages} ->
      %{
        id: t.id,
        title: t.title,
        lead: nil,
        stage: t.stage,
        awaiting: t.awaiting,
        active?: t.id == focus,
        typing: typing_agent(Map.get(thinking, t.id, %{})),
        messages: if(t.id == opened, do: messages, else: [])
      }
    end)
  end

  defp typing_agent(thinking) when map_size(thinking) == 0, do: nil
  defp typing_agent(thinking), do: thinking |> Map.keys() |> List.first() |> String.replace_suffix("-machine", "")

  # Entering the PTY, point the center's tmux client at the FOCUSED thread's own lead window (its
  # `t<id>`) so `v` on a thread shows THAT thread's agent, not whatever the standing coworker was on
  # (Andrew: "v takes me to pi"). A root/window-less thread leaves the client where it is.
  defp select_focused_window(%{active_key: key, stack_focus: id}) when Space.workspace?(key) and is_integer(id) do
    case leaf_tab(tlon_tabs(key), id) do
      %{index: idx} -> tlon_run(key, ["select-window", "-t", "#{workspace_session(key)}:#{idx}"])
      _ -> :ok
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp select_focused_window(_state), do: :ok

  defp active_workspace_id(%{active_key: key}) when Space.workspace?(key), do: key

  defp active_workspace_id(_state) do
    case Space.first_workspace() do
      nil -> nil
      space -> space.id
    end
  end

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
  defp tlon_window_index(workspace_id, name), do: window_index(tlon_tabs(workspace_id), name)

  # Same lookup against an already-fetched tabs list — for a caller (`ensure_thread_sessions`)
  # that snapshot tlon_tabs() once for a whole render pass instead of forking `tmux` per thread.
  defp window_index(tabs, name) do
    Enum.find_value(tabs, fn %{name: n, index: index} -> if n == name, do: index end)
  end

  # Inject `text` as a submitted turn into window `index` of workspace `workspace_id`: literal text, then
  # the Enter key — so a multiline body flattened to one line reaches the coworker's input as a
  # single message. Safe for a LONG-BOOTED window (the standing coworkers); a freshly-spawned
  # harness needs the split form below (`inject_text`/`submit_turn`) so the Enter doesn't get
  # swallowed in the same input burst.
  defp inject_turn(workspace_id, index, text) do
    inject_text(workspace_id, index, text)
    submit_turn(workspace_id, index)
  end

  # Type literal `text` into window `index` of workspace `workspace_id` WITHOUT submitting — the first half
  # of a fresh-window inject, so the Enter can be sent on a later render once the TUI has settled.
  defp inject_text(workspace_id, index, text) do
    _ = tlon_run(workspace_id, ["send-keys", "-l", "-t", "#{workspace_session(workspace_id)}:#{index}", text])
    :ok
  end

  # Send Enter to window `index` of workspace `workspace_id` — submits whatever's in its input. Split from
  # `inject_text` so a just-booted Claude Code TUI gets the text and the Enter as separate bursts (a
  # bundled Enter lands as a literal newline / gets swallowed, leaving the turn typed-but-unsent).
  defp submit_turn(workspace_id, index) do
    _ = tlon_run(workspace_id, ["send-keys", "-t", "#{workspace_session(workspace_id)}:#{index}", "Enter"])
    :ok
  end

  defp dispatch_wheel(nil, _b, _x, _y, state), do: {:noreply, state}

  # While the lazygit overlay is up, wheel events belong to ITS PTY, not the center terminal (Slice 4).
  defp dispatch_wheel({Panel.Terminal, _data, rect}, b, x, y, %{lazygit: %{thread_id: id}} = state) do
    with term when is_pid(term) <- safe_terminal({:lazygit, id}),
         {dir, n} <- Mouse.wheel_of(b) do
      lx = clamp_cell(x - rect.x, rect.w)
      ly = clamp_cell(y - rect.y, rect.h)
      repaint_on_scroll(Terminal.wheel(term, dir, n, lx, ly), state)
    else
      _ -> {:noreply, state}
    end
  end

  # The center terminal: forward to the embedded app if it tracks the mouse, else scroll scrollback.
  defp dispatch_wheel({Panel.Terminal, _data, rect}, b, x, y, state) do
    with term when is_pid(term) <- center_terminal(state),
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

  defp repaint_on_scroll(:scrolled, state), do: {:noreply, render(state)}
  defp repaint_on_scroll(:forwarded, state), do: {:noreply, state}

  defp dispatch_click(nil, _x, _y, state), do: {:noreply, state}

  # Clicking the center terminal: forward to the PTY when the embedded program tracks the mouse
  # (tmux `mouse on` selects; a TUI hit-tests its own regions). The terminal renders edge-to-edge.
  # While the lazygit overlay is up, its Panel.Terminal is the hit target — route the click to THAT
  # PTY, not the machine center terminal underneath (Slice 4).
  defp dispatch_click({Panel.Terminal, _data, rect}, x, y, %{lazygit: %{thread_id: id}} = state) do
    with term when is_pid(term) <- safe_terminal({:lazygit, id}) do
      Terminal.mouse(term, :press, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
    end

    {:noreply, state}
  end

  defp dispatch_click({Panel.Terminal, _data, rect}, x, y, state) do
    with term when is_pid(term) <- center_terminal(state) do
      Terminal.mouse(term, :press, clamp_cell(x - rect.x, rect.w), clamp_cell(y - rect.y, rect.h))
    end

    {:noreply, state}
  end

  # --- The overlay menu (right-click workspace context menu + icon picker, Slice 3.5) ---
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

  # Select a Tlön tmux window in workspace `workspace_id` by the clicked/hovered tab's index; nil (past the
  # tabs) is a no-op.
  defp select_tlon_window(workspace_id, %{index: idx}) do
    tlon_run(workspace_id, ["select-window", "-t", "#{workspace_session(workspace_id)}:#{idx}"])
    :ok
  end

  defp select_tlon_window(_workspace_id, _tab), do: :ok

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

  # --- The full-screen boards (Tickets / Notes, Slice 3.5): the spine tools zoom to a board that
  # covers the frame; Esc closes it. Painted after the layout, before the menu. ---
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
    tickets = safe_board(fn -> id && id |> Server.Tickets.in_workspace() |> Enum.map(&ticket_row/1) end) || []

    {Panel.TicketBoard, %{tickets: tickets, cursor: state.board_cursor},
     "TICKETS · h/l·j/k move · p advance · n new · ⏎ promote"}
  end

  defp board_content(:notes, state) do
    id = board_workspace_id(state)
    notes = safe_board(fn -> id && Server.Notes.for_scope("workspace", id) end) || []
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
    tickets = safe_board(fn -> id && Server.Tickets.in_workspace(id) end) || []
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
        _ = safe_board(fn -> Server.Tickets.update(ticket, %{status: next}) end)
        %{state | flash: "ticket ##{ticket.id} → #{next}"}

      _ ->
        state
    end
  end

  defp promote_selected_ticket(state) do
    case selected_ticket(state, ticket_columns(state)) do
      %{id: id, title: title} = ticket ->
        with {:ok, thread} <-
               Channel.open_thread(%{title: title, workspace_id: active_workspace_id(state), scope: "machine"}),
             {:ok, _} <- safe_board(fn -> Server.Tickets.promote(ticket, thread.id) end) do
          _ = spawn_onto(thread.id, state)
          %{state | board: nil, focused_id: thread.id, flash: "promoted ticket ##{id} → thread"}
        else
          _ -> %{state | flash: "couldn't promote the ticket"}
        end

      _ ->
        state
    end
  end

  # --- The STACK-zoom embedded lazygit overlay (Slice 4): a full-frame `Panel.Terminal` over the
  # lazygit PTY, painted like a board. `render_state_of` yields the live cell grid or `:no_session`
  # (the tick reconciles a vanished terminal back to `lazygit: nil`). ---
  defp lazygit_placements(%{lazygit: nil}), do: []

  defp lazygit_placements(%{lazygit: %{thread_id: id, path: path}, w: w, h: h}) do
    rect = %{x: 0, y: 0, w: w, h: max(h - 1, 2)}
    inset = %{x: 1, y: 1, w: max(w - 2, 1), h: max(h - 3, 1)}
    title = "lazygit · #{Path.basename(path)}  ·  ^space to close"

    [
      {Panel.Border, %{focused: true, digit: nil, title: title, tabs: nil, hint: nil}, rect},
      {Panel.Terminal, render_state_of(safe_terminal({:lazygit, id})), inset}
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
    if Console.Lazygit.available?() do
      case Server.worktree_for_thread(id) do
        {:ok, cwd} -> spawn_lazygit(state, id, cwd)
        {:error, reason} -> {:noreply, render(%{state | flash: "no repo for this thread (#{inspect(reason)})"})}
      end
    else
      {:noreply, render(%{state | flash: "lazygit is not installed"})}
    end
  rescue
    e -> {:noreply, render(%{state | flash: "lazygit failed: #{Exception.message(e)}"})}
  catch
    :exit, reason -> {:noreply, render(%{state | flash: "lazygit failed: #{inspect(reason)}"})}
  end

  defp spawn_lazygit(state, id, cwd) do
    {cmd, args} = Console.Lazygit.command(cwd)
    {cols, rows} = {max(state.w - 2, 1), max(state.h - 3, 1)}

    case safe_lazygit_spawn(id, cmd, args, cols, rows) do
      {:ok, _pid} -> {:noreply, render(%{state | lazygit: %{thread_id: id, path: cwd}})}
      _ -> {:noreply, render(%{state | flash: "couldn't start lazygit"})}
    end
  end

  # Sessions is supervised but the cockpit is not — a call to a downed registry would crash the frame.
  defp safe_lazygit_spawn(id, cmd, args, cols, rows) do
    Sessions.ensure({:lazygit, id}, cmd: cmd, args: args, cols: cols, rows: rows)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  # Collapse a lazygit overlay whose terminal has exited (quit from inside) — else it paints
  # `:no_session` over the frame. A no-op while the terminal is live or no overlay is up.
  defp reconcile_lazygit(%{lazygit: %{thread_id: id}} = state) do
    if is_pid(safe_terminal({:lazygit, id})), do: state, else: %{state | lazygit: nil}
  end

  defp reconcile_lazygit(state), do: state

  defp ticket_row(t), do: %{id: t.id, title: t.title, status: t.status, priority: t.priority, assignee: t.assignee}

  # The workspace whose tickets/notes the board shows: the active one, or the default (Orbis falls
  # back to the first workspace via active_workspace_id/1).
  defp board_workspace_id(state), do: active_workspace_id(state)

  defp safe_board(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # State transitions live in the pure `Console.Keymap`; the Cockpit only runs the side effect it
  # asks for — repaint, quit, or forward a key to the focused terminal.
  defp apply_effect(:repaint, state), do: {:noreply, render(state)}
  defp apply_effect(:none, state), do: {:noreply, state}
  defp apply_effect(:quit, state), do: quit(state)

  # A focused key goes to the focused session's embedded terminal: encode it as a Ghostty.KeyEvent
  # and hand it to the emulator, which writes the right bytes straight to the PTY — one native
  # keystroke, no shell-out. An unmappable key is dropped rather than misdelivered.
  defp apply_effect({:forward, key}, state) do
    with %KeyEvent{} = event <- ghostty_key(key),
         term when is_pid(term) <- center_terminal(state) do
      Terminal.send_key(term, event)
    end

    {:noreply, state}
  end

  defp apply_effect({:create_thread, text}, state) do
    # The typed text is the OPENING MESSAGE, not just a title: post it as the operator so the thread
    # reads as a real chat and its lead has something to answer (the "no messages yet / silent agent"
    # bug). The title is a short slug of it. scope: "machine" so it shows in the stack.
    operator = Application.get_env(:server, :operator, "andrew")

    case Channel.open_thread(%{title: thread_title(text), workspace_id: active_workspace_id(state), scope: "machine"}) do
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
    case safe_board(fn -> Server.Tickets.file(%{workspace_id: active_workspace_id(state), title: title}) end) do
      {:ok, t} -> {:noreply, render(%{state | flash: "filed ticket ##{t.id} in backlog"})}
      _ -> {:noreply, render(%{state | flash: "couldn't file the ticket"})}
    end
  end

  # First-class note create (Slice C): a workspace-scoped note, authored by the operator.
  defp apply_effect({:write_note, body}, state) do
    operator = Application.get_env(:server, :operator, "andrew")
    attrs = %{body: body, scope: "workspace", scope_id: active_workspace_id(state), author: operator}

    case safe_board(fn -> Server.Notes.write(attrs) end) do
      {:ok, n} -> {:noreply, render(%{state | flash: "noted ##{n.id}"})}
      _ -> {:noreply, render(%{state | flash: "couldn't save the note"})}
    end
  end

  # The tertius command line (Slice 1): route the typed meta-intent and flash a RECEIPT — a line you
  # talk into with no confirmation is the exact bug this repo opened on 2026-08-30. SAFE verbs
  # (post/note/ticket/query) fire straight; CONSEQUENTIAL ones (open work, approve) ARM the y/n gate
  # (`pending_confirm`) — showing what they WOULD do and firing nothing until the operator says `y`
  # (Console.Keymap → `:confirm_orchestrate`). Slice 3.5.
  defp apply_effect({:orchestrate, text}, state) do
    action = Console.Orchestrator.Router.route(text)
    ctx = %{workspace_id: active_workspace_id(state), operator: Application.get_env(:server, :operator, "andrew")}

    case {Console.Orchestrator.classify(action), Console.Orchestrator.dispatch(action, ctx)} do
      {:consequential, {:confirm, summary}} ->
        arm = %{action: action, ctx: ctx, summary: summary}
        {:noreply, render(%{state | pending_confirm: arm, flash: "⏸ #{summary}? — y to confirm · n to cancel"})}

      {_class, result} ->
        flash_receipt(result, state)
    end
  rescue
    e -> {:noreply, render(%{state | flash: "orchestrate failed: #{Exception.message(e)}"})}
  catch
    :exit, reason -> {:noreply, render(%{state | flash: "orchestrate failed: #{inspect(reason)}"})}
  end

  # `y` on an armed consequential verb (Console.Keymap): fire it now, log the receipt. The arm rode the
  # effect (the keymap already cleared `pending_confirm`), so this is a clean one-shot.
  defp apply_effect({:confirm_orchestrate, %{action: action, ctx: ctx}}, state) do
    flash_receipt(Console.Orchestrator.confirm(action, ctx), state)
  rescue
    e -> {:noreply, render(%{state | flash: "confirm failed: #{Exception.message(e)}"})}
  catch
    :exit, reason -> {:noreply, render(%{state | flash: "confirm failed: #{inspect(reason)}"})}
  end

  # The `c` verb landed: post the composer's body to the focused thread AS THE OPERATOR (config
  # `:server, :operator`), so a posted message is the human's voice, not an agent's. The Bus
  # announce repaints the chorus live, so the message lands visibly; a failure flashes in the footer.
  defp apply_effect({:post_message, thread_id, body}, state) do
    operator = Application.get_env(:server, :operator, "andrew")

    case Channel.post(%{thread_id: thread_id, author: operator, body: body}) do
      {:ok, _message} -> {:noreply, render(%{state | flash: "posted"})}
      {:error, _changeset} -> {:noreply, render(%{state | flash: "couldn't post — is the thread open?"})}
    end
  rescue
    e -> {:noreply, render(%{state | flash: "post failed: #{Exception.message(e)}"})}
  catch
    :exit, reason -> {:noreply, render(%{state | flash: "post failed: #{inspect(reason)}"})}
  end

  # The composer's /status command (reshape slice D): the full HEALTH readout — the panel demoted
  # to a footer line — as a MAIN detail in a Workspace space; Esc closes it like any detail. Orbis has
  # no detail surface (and no health probe), so it degrades to an honest flash.
  defp apply_effect({:show_status, _thread_id}, %{active_key: key} = state) when Space.workspace?(key) do
    state = %{put_in(state.focus.detail?, true) | status_detail: status_detail_content(state.health)}
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
  defp apply_effect({:cycle_coworker_model, profile_name}, state) do
    {:noreply, render(%{state | flash: cycle_model!(profile_name)})}
  rescue
    e -> {:noreply, render(%{state | flash: "settings write failed: #{Exception.message(e)}"})}
  end

  # Enter in Tlön nav: on the Sidebar, switch to the space under the cursor; on STACK, zoom the
  # focused thread's worktree into an embedded lazygit (Slice 4); on any other pane, open its
  # selection's detail in MAIN (set focus.detail?, which the View renders).
  defp apply_effect(:tlon_enter, state) do
    # A pane Enter always resolves ITS detail — never a leftover /status readout.
    state = %{state | status_detail: nil}
    layout = tlon_layout(state)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Sidebar -> apply_pick({:switch_space, space_at_cursor(state, layout)}, state)
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
    case Enum.at(tlon_tabs(key), n - 1) do
      %{index: idx} -> select_tlon_window(key, %{index: idx})
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
    case selected_habit(state) do
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
  rescue
    e -> {:noreply, render(%{state | flash: "habit action failed: #{Exception.message(e)}"})}
  end

  # `d` in Tlön nav landed: arm the two-key confirm on the focused pane's selection — a MEMORY
  # pinned fact (forget) or a LEAVES leaf (window + thread). Anywhere else: flash the miss.
  defp apply_effect(:tlon_delete_arm, state) do
    case tlon_delete_target(state) do
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
    flash =
      case Server.delete_thread(id) do
        {:ok, thread} -> "deleted “#{thread.title}”"
        {:error, :root_machine_thread} -> "can't delete the root thread"
        {:error, reason} -> "delete refused: #{inspect(reason)}"
      end

    {:noreply, render(%{state | tlon_delete: nil, flash: flash})}
  rescue
    e -> {:noreply, render(%{state | flash: "delete failed: #{Exception.message(e)}"})}
  end

  # The second `d` (still armed) landed: execute against the ARM-TIME target.
  defp apply_effect({:tlon_delete, {:fact, fact, _label}}, state) do
    flash =
      case Dossier.forget_fact(fact) do
        {:ok, _} -> "forgot fact ##{fact.id}"
        _ -> "couldn't forget fact ##{fact.id}"
      end

    {:noreply, render(%{state | memory: nil, flash: flash})}
  rescue
    e -> {:noreply, render(%{state | flash: "forget failed: #{Exception.message(e)}"})}
  end

  # `y` landed: resolve the focused pane's semantic text, OSC-52 it to the host clipboard
  # (through the tty, so it works over SSH), and flash what was taken.
  defp apply_effect(:yank, state) do
    case yank_text(state) do
      {label, text} ->
        IO.write(Osc.copy(text))
        {:noreply, render(%{state | flash: "yanked #{label}"})}

      nil ->
        {:noreply, render(%{state | flash: "nothing to yank here"})}
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
  rescue
    e -> %{state | flash: "create failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "create failed: #{inspect(reason)}"}
  end

  @doc false
  # Remove workspace `id` (D2.5's second `d`). Guards against stranding the cockpit on a deleted
  # active workspace (falls back to `:orbis`) and clamps `author_cursor` to the shrunk list. A missing
  # workspace (already gone) or a server hiccup flashes, never crashes.
  def remove_workspace!(state, id) do
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
  rescue
    e -> %{state | flash: "delete failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "delete failed: #{inspect(reason)}"}
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
    case Workspaces.get(id) do
      nil ->
        %{state | flash: "workspace ##{id} already gone"}

      workspace ->
        case Workspaces.edit(workspace, attrs) do
          {:ok, updated} -> reclamp_author_edit_sub(%{state | flash: "updated #{updated.name}"})
          {:error, changeset} -> %{state | flash: "couldn't update #{workspace.name} — #{changeset_error(changeset)}"}
        end
    end
  rescue
    e -> %{state | flash: "edit failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "edit failed: #{inspect(reason)}"}
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
    case roster_entry_for(state, name) do
      nil -> %{state | flash: "#{name}: roster entry not found"}
      entry -> %{state | flash: apply_knob(entry, knob)}
    end
  rescue
    e -> %{state | flash: "settings write failed: #{Exception.message(e)}"}
  catch
    :exit, reason -> %{state | flash: "settings write failed: #{inspect(reason)}"}
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

  # The pending habit the focus points at, or nil unless: a Workspace space, nav mode, Memory pane,
  # habits section (1), with a habit under the clamped cursor.
  defp selected_habit(
         %{active_key: key, memory: %{habits: habits}, focus: %{in_terminal?: false, section: 1} = focus} = state
       )
       when Space.workspace?(key) do
    layout = tlon_layout(state)
    if Focus.focused_pane(focus, layout) == Panel.Memory, do: Enum.at(habits, Focus.cursor(focus, layout))
  end

  defp selected_habit(_state), do: nil

  # What `d` would delete under the current focus: a MEMORY pinned fact (forget). The label rides
  # along for the arm flash.
  defp tlon_delete_target(state) do
    case selected_pinned_fact(state) do
      nil -> nil
      fact -> {:fact, fact, "forget fact ##{fact.id}"}
    end
  end

  # The pinned fact the focus points at — selected_habit's twin for the pinned section (0).
  defp selected_pinned_fact(
         %{active_key: key, memory: %{pinned: pinned}, focus: %{in_terminal?: false, section: 0} = focus} = state
       )
       when Space.workspace?(key) do
    layout = tlon_layout(state)
    if Focus.focused_pane(focus, layout) == Panel.Memory, do: Enum.at(pinned, Focus.cursor(focus, layout))
  end

  defp selected_pinned_fact(_state), do: nil

  # Spawn a harness as an embedded terminal on this thread: mint identity IN-PROCESS
  # (Server.MCP.Spawn.join — console is the serving node) and start an Console.Terminal that runs the
  # launcher with the TLON_* env sourced (and TERM set, so the harness produces colour). One
  # native PTY per thread, rendered in the center. A raise/exit becomes a flash, never a crash.
  defp spawn_onto(thread_id, state) do
    agent = Application.get_env(:console, :spawn_agent, "pi")
    {cols, rows} = center_dims(state)

    case Spawn.join(thread_id, agent) do
      {:ok, %{exports: exports}} ->
        case safe_spawn_harness(thread_id, exports, cols: cols, rows: rows) do
          {:ok, _pid} -> "session live — type to use it, Ctrl+Space for console"
          {:error, reason} -> "spawn failed: #{inspect(reason)}"
        end

      {:error, reason} ->
        "spawn failed: #{inspect(reason)}"
    end
  rescue
    e -> "spawn crashed: #{Exception.message(e)}"
  catch
    :exit, reason -> "spawn crashed: #{inspect(reason)}"
  end

  # console key event → Ghostty.KeyEvent (public + tested: a missing mapping silently drops a key).
  @doc false
  def ghostty_key(%{key: :char, char: c} = ev),
    do: %KeyEvent{key: char_key(c), utf8: c, mods: mods(ev), unshifted_codepoint: unshifted_codepoint(c)}

  def ghostty_key(%{key: :up} = ev), do: %KeyEvent{key: :arrow_up, mods: mods(ev)}
  def ghostty_key(%{key: :down} = ev), do: %KeyEvent{key: :arrow_down, mods: mods(ev)}
  def ghostty_key(%{key: :left} = ev), do: %KeyEvent{key: :arrow_left, mods: mods(ev)}
  def ghostty_key(%{key: :right} = ev), do: %KeyEvent{key: :arrow_right, mods: mods(ev)}

  def ghostty_key(%{key: k} = ev)
      when k in [:enter, :tab, :backspace, :delete, :escape, :space, :home, :end, :page_up, :page_down],
      do: %KeyEvent{key: k, mods: mods(ev)}

  def ghostty_key(_key), do: nil

  # a-z (and A-Z → the lowercase key + a shift mod via utf8), 0-9 → :digit_N; anything else is
  # carried by utf8 alone under :unidentified.
  # to_atom, NOT to_existing_atom: the char set is bounded (a-z, A-Z, 0-9 → 36 known atoms), so there's
  # no atom-table-exhaustion risk — and to_existing_atom CRASHES the cockpit on any letter whose atom
  # wasn't already interned (e.g. pressing "o" when :o exists nowhere as a literal). The ghostty_key
  # unit tests masked this: their :x/:c/:v literals intern exactly those atoms at compile time.
  defp char_key(<<cp>>) when cp in ?a..?z, do: String.to_atom(<<cp>>)
  defp char_key(<<cp>>) when cp in ?A..?Z, do: String.to_atom(<<cp + 32>>)
  defp char_key(<<cp>>) when cp in ?0..?9, do: String.to_atom("digit_#{<<cp>>}")
  defp char_key(_c), do: :unidentified

  # The Kitty encoder needs the unshifted codepoint to build \e[<cp>;<mods>u for a modified
  # printable (ctrl+v → \e[118;5u); without it modifiers are dropped (ctrl+v → "v"). Letters use
  # their lowercase codepoint. KNOWN LIMIT: a shifted symbol (shift+2 → "@") can't be recovered
  # here (the host keyboard layout is gone by this layer) — no current binding hits that path.
  defp unshifted_codepoint(c) do
    c |> String.downcase() |> String.to_charlist() |> List.first() || 0
  end

  defp mods(ev) do
    [{:ctrl, ev[:ctrl]}, {:alt, ev[:alt]}, {:shift, ev[:shift]}]
    |> Enum.filter(fn {_mod, on?} -> on? end)
    |> Enum.map(fn {mod, _} -> mod end)
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
  # Board.safe_read — one bad read renders as that panel's quiet state while the rest of the frame
  # stays live — and this wrapper is the backstop for anything left (View.compose, the paint): log
  # and keep the previous frame's state instead of dying. The read seam is exactly where the
  # 2026-08-28 DateTime crash rode past safe_rows (crew_read raised upstream of any panel render)
  # and took the whole cockpit down.
  defp render(state) do
    do_render(state)
  rescue
    e ->
      Console.CrashLog.append("render error", Exception.format(:error, e, __STACKTRACE__))
      state
  catch
    kind, reason ->
      Console.CrashLog.append("render error", Exception.format(kind, reason, __STACKTRACE__))
      state
  end

  defp do_render(state) do
    # Fill the probe cache (Tlön only) and find-or-spawn the Workspace's roster — both stateful,
    # both rate-limited, both OUT of the per-frame hot path. Each step degrades to the state it
    # was handed, so a tmux/server hiccup skips that step this frame instead of losing the frame.
    state = Board.safe_read(:probes, state, fn -> ensure_probes(state) end)
    state = Board.safe_read(:workspace_roster, state, fn -> ensure_workspace_roster(state) end)
    state = Board.safe_read(:thread_sessions, state, fn -> ensure_thread_sessions(state) end)
    state = Board.safe_read(:session_pane, state, fn -> ensure_session(state) end)

    # The thread-stack blocks (Slice 3): machine-scope threads + their messages — the Tlön cockpit's
    # threads ARE machine-scope, so the stack AND the cockpit's nav (`j`/`k`/`↑`/`↓` via `move/2`)
    # order by this, not the project-scope `chorus`. This is the ONE ordering the cockpit navigates.
    stack_blocks = Board.safe_read(:stack, [], fn -> Channel.machine_threads(active_workspace_id(state)) end)
    threads = Enum.map(stack_blocks, & &1.thread)
    focused = focused_thread(threads, state.focused_id)
    state = %{state | threads: threads, focused_id: focused && focused.id}
    state = %{state | stack_focus: stack_focus(stack_blocks, state.focused_id)}
    state = Board.safe_read(:resubscribe, state, fn -> resubscribe(state, focused) end)
    machine = Board.safe_read(:machine, :no_session, fn -> machine_read(state) end)
    roster = Board.safe_read(:roster, [], fn -> Staff.roster() end)

    # Computed once — the layout read and the detail read below share it (the detail is resolved
    # against the same frame's layout).
    tlon_layout =
      Board.safe_read(:tlon_layout, nil, fn -> if(Space.workspace?(state.active_key), do: tlon_layout(state)) end)

    reads = %{
      active_key: state.active_key,
      focused_id: focused && focused.id,
      focused_title: focused && focused.title,
      roster: roster,
      threads: threads,
      # The thread-stack center (Slice 3): machine threads as foldable cards; the block carries each
      # thread's messages, so an unfolded card is free. `zoomed` collapses it to one full card.
      thread_stack: %{
        cards: thread_cards(stack_blocks, state.stack_focus, state.opened_thread, state.thinking),
        opened: state.opened_thread
      },
      # The Slack sidebar's read-model (reshape slice C): workspace groups with their unified
      # thread list + crew working flags.
      sidebar: Board.safe_read(:sidebar, [], fn -> Server.Board.sidebar() end),
      # Kitty host? → the Sidebar blanks its fallback glyph so the icon PNG covers cleanly (no bleed).
      graphics?: Console.Graphics.kitty?(),
      workspaces:
        Board.safe_read(:workspaces, [], fn -> if(state.active_key == :orbis, do: orbis_workspaces(state), else: []) end),
      # The survey's focus + per-row cursor, so Overview can wash the cursor row :selected — only
      # meaningful in Orbis (a meaningless-but-harmless read elsewhere).
      orbis_focus: state.orbis_focus,
      survey_cursor: state.survey_cursor,
      # Orbis' author face (D2.1/D2.2): which center panel to render, and its own cursor.
      # Meaningless-but-harmless outside Orbis.
      orbis_face: state.orbis_face,
      author_cursor: state.author_cursor,
      # The field editor (D2.4 Chunk 2a): nil unless `e` opened it. Meaningless-but-harmless
      # outside Orbis' author face.
      author_edit: state.author_edit,
      machine: machine,
      crew: Board.safe_read(:crew, nil, fn -> crew_read(state, machine) end),
      stack: state.stack || @empty_stack,
      health: state.health,
      activity: scope_activity(state.activity, state.ws_thread_ids),
      gates: state.gates || [],
      memory: if(Space.workspace?(state.active_key), do: state.memory),
      # The center's face (reshape slice D).
      center_view: state.center_view,
      triage: Board.safe_read(:triage, nil, fn -> if(state.active_key == :orbis, do: triage_read(threads)) end),
      scrolls: state.scrolls,
      input: state.input,
      flash: state.flash,
      receipts: state.receipts,
      leader_pending?: state.leader_pending?,
      # LOCK mode (design 2026-08-23) — the footer's loudest chip.
      lock?: state.lock?,
      # The Workspace space's focus, so the View can light the focused sidebar pane and the status bar
      # can show NAV/TERM. nil elsewhere — no other space navigates panes this way.
      focus: if(Space.workspace?(state.active_key), do: state.focus),
      # The layout the View reads for the focused pane + item cursor (counts), and the resolved
      # MAIN detail (nil unless the focus opened one). Both nil outside a Workspace space.
      tlon_layout: tlon_layout,
      # The right SESSION PANE (2026-08-31): the selected thread's id when the pane is toggled on
      # (else nil → no right column), and its embedded lead PTY render-state. View.compose splits a
      # right column off the center when the target is set.
      session_pane: session_pane_target(state),
      session: Board.safe_read(:session, :no_session, fn -> session_read(state) end),
      detail:
        Board.safe_read(:detail, nil, fn ->
          if(Space.workspace?(state.active_key) and state.focus.detail?, do: tlon_detail(state, tlon_layout))
        end)
    }

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

  defp focused_thread([], _id), do: nil
  defp focused_thread(threads, nil), do: List.first(threads)
  defp focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The reconcile-on-connect read: whatever the store already holds when the cockpit boots
  # (declares made before this subscribe). Degrades to empty if the store isn't up.
  defp thinking_snapshot do
    Map.new(Server.Presence.Thinking.thinking_all(), fn {tid, entries} ->
      # Same normalization as the live event path — cockpit state holds unix seconds.
      {tid, Map.new(entries, &{&1.agent, Console.Presence.started_s(&1.started_at)})}
    end)
  catch
    :exit, _ -> %{}
  end

  # The CREW sidebar's read: the active Workspace's roster joined with the tmux snapshot, the leaf
  # leads, and the thinking declarations (Console.Panel.Crew.coworkers/6). Lead lookups go one
  # server query per live leaf window — at most the leaf cap.
  defp crew_read(state, %{tabs: tabs}) do
    led_by =
      tabs
      |> Enum.filter(&is_integer(&1.thread_id))
      |> Enum.reduce(%{}, fn %{thread_id: tid}, acc ->
        case Server.thread_lead(tid) do
          lead when is_binary(lead) -> Map.update(acc, lead, [tid], &[tid | &1])
          _ -> acc
        end
      end)

    titles = Map.new(state.threads, &{&1.id, &1.title})
    roster = active_roster(active_workspace_id(state))

    %{
      coworkers: Panel.Crew.coworkers(roster, tabs, led_by, titles, state.thinking, System.os_time(:second)),
      leaves: {Enum.count(tabs, &leaf_window?/1), Console.Config.max_leaves()}
    }
  end

  defp crew_read(_state, _machine), do: nil

  # The Tlön center's read: the embedded tmux client. Lookup only — the find-or-spawn lives in
  # ensure_center (render's stateful preamble, via ensure_workspace_roster), so a failing spawn can back
  # off instead of re-materialising the profile and re-issuing tmux new-session every frame.
  defp machine_read(%{active_key: key}) when Space.workspace?(key) do
    case render_state_of(safe_terminal(:machine)) do
      %{} = render_state -> Map.put(render_state, :tabs, tlon_tabs(key))
      other -> other
    end
  end

  defp machine_read(_state), do: :no_session

  # The right session pane's TARGET: the stack-focused thread's id when the pane is toggled on in a
  # workspace chat view, else nil (the pane is hidden). Follows the cursor — moving j/k re-targets it,
  # so the pane always shows whatever thread you're looking at.
  defp session_pane_target(%{session_pane: true, active_key: key, center_view: :chat, stack_focus: id})
       when Space.workspace?(key) and is_integer(id), do: id

  defp session_pane_target(_state), do: nil

  # The session pane's embedded terminal render-state — the selected thread's live lead PTY, keyed
  # `{:session, id}` in Console.Sessions, or `:no_session` until spawned. LIVE seam: `ensure_session`
  # spawns/attaches the PTY (render + key routing are Andrew's kitty pass).
  defp session_read(state) do
    case session_pane_target(state) do
      id when is_integer(id) -> render_state_of(safe_terminal({:session, id}))
      _ -> :no_session
    end
  end

  # Spawn (or reuse) the selected thread's lead session PTY when the pane is on — a tmux client
  # attached to the thread's lead window in the workspace session (`Console.SessionPane.command/1`).
  # Rate-limited out of the hot path like the other ensure_* preamble steps; a miss just leaves the
  # pane on `:no_session` this frame. LIVE-tunable (the attach shape is the kitty pass).
  defp ensure_session(state) do
    with id when is_integer(id) <- session_pane_target(state),
         nil <- session_terminal_pid(id),
         %{index: index} <- leaf_tab(tlon_tabs(active_workspace_id(state)), id) do
      ws = active_workspace_id(state)
      {cmd, args} = Console.SessionPane.command(workspace_socket(ws), workspace_session(ws), index)
      {cols, rows} = session_pane_dims(state)
      _ = safe_session_spawn(id, cmd, args, cols, rows)
    end

    state
  end

  defp session_terminal_pid(id) do
    case safe_terminal({:session, id}) do
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end

  defp safe_session_spawn(id, cmd, args, cols, rows) do
    Sessions.ensure({:session, id}, cmd: cmd, args: args, cols: cols, rows: rows)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  # The session pane occupies the right column (~⅓ of the center's width) — spawn dims only; the live
  # resize-on-window-change is the kitty pass.
  defp session_pane_dims(%{w: w, h: h}), do: {max(div(w, 3) - 2, 1), max(h - 3, 1)}

  defp render_state_of(nil), do: :no_session
  defp render_state_of(term), do: Terminal.render_state(term)

  # Sessions is supervised (Console.Supervisor) but the cockpit is NOT — a `Sessions.terminal/1`
  # against a torn-down registry raises `(EXIT) no process`, which would otherwise propagate up
  # through render and kill the cockpit, wedging all input (Enter would go nowhere). Degrade to
  # nil so a dead registry just reads as "no session"; the supervisor restarts it on its own.
  defp safe_terminal(thread_id) do
    Sessions.terminal(thread_id)
  catch
    :exit, _ -> nil
  end

  defp safe_spawn_harness(thread_id, exports, opts) do
    Sessions.spawn_harness(thread_id, exports, opts)
  catch
    :exit, _ -> {:error, :sessions_down}
  end

  # The terminal that owns the keys, by space: a Workspace → the embedded tmux client (still the single
  # `:machine` registry entry in Slice 1 — C2 keys the terminal per workspace id). nil elsewhere (Orbis
  # has no center Terminal — its surface is the Overview).
  defp center_terminal(%{active_key: key}) when Space.workspace?(key), do: safe_terminal(:machine)
  defp center_terminal(_state), do: nil

  # The thread `c` composes onto, derived per keypress (like center_live?): the focused project
  # thread in Orbis; in a Workspace space, whoever you're actually LOOKING at (reshape slice D:
  # the thread is the address, fixing the "who am I talking to" decoupling) — in chat view
  # (Slice 3.3) that's the stack-focused card (the unfolded thread on screen); in terminal view
  # it's the MACHINE thread. nil (no thread) makes `c` a no-op.
  @doc false
  def composer_thread_id(%{active_key: key, center_view: :chat, stack_focus: focus})
      when Space.workspace?(key) and not is_nil(focus) do
    focus
  end

  def composer_thread_id(%{active_key: key} = state) when Space.workspace?(key),
    do: machine_thread_id(active_workspace_id(state))

  def composer_thread_id(state), do: state.focused_id

  @doc false
  # The pure flip behind the `v` verb — exposed for TTY-less tests.
  def toggle_center_view(%{center_view: :chat} = state), do: %{state | center_view: :terminal}
  def toggle_center_view(state), do: %{state | center_view: :chat}

  # The shape the Tlön focus SM navigates: the space's two sidebar columns, per-pane section counts
  # (empty until a multi-section pane lands — Memory's coverage/pinned/habits split), and per-pane
  # ITEM counts (what j/k clamps against), derived from the live reads in `state`. Keyed by pane
  # module, matching space.left/right. nil-ish layout for other spaces (the keymap only reads it in
  # Tlön anyway).
  # The Sidebar leads the left column in the FOCUS layout exactly as it does on screen (View
  # prepends it to `space.left`), so `h`/`H` can land on the workspace nav and `Enter` switches.
  defp tlon_layout(%{active_key: key} = state) when Space.workspace?(key) do
    case Space.fetch(key) do
      # A stale/removed active_key mid-render (Space.fetch/1 returns nil on a miss) — degrade to
      # the same empty layout a non-Workspace space gets, rather than crash the render.
      nil ->
        %{left: [], right: [], sections: %{}, counts: %{}}

      space ->
        %{
          # Nav v2 (Andrew 2026-08-31): the focus nav is the RAIL alone (`space.left`) — the spine is
          # click/keybind only, not keyboard-navigable. h/l walks the rail; there are no pane digits.
          left: space.left,
          right: [],
          sections: %{Panel.Memory => memory_sections(state)},
          counts: pane_counts(state)
        }
    end
  end

  defp tlon_layout(_state), do: %{left: [], right: [], sections: %{}, counts: %{}}

  # HABITS collapses when empty (Panel.Memory), so the Tab ring must shrink with it.
  defp memory_sections(%{memory: %{habits: habits}}) when habits != [], do: 2
  defp memory_sections(_state), do: 1

  defp space_at_cursor(state, layout), do: Enum.at(Space.all(), Focus.cursor(state.focus, layout)).key

  # The navigable item count per pane, for j/k clamping. Commits = the commit-log length; Memory is
  # sectioned — j/k walks the ACTIVE section's list (pinned=0, habits=1), so its count follows
  # focus.section. Panes without a list are absent (0 → j/k is a no-op there).
  defp pane_counts(state) do
    # Nav v2: the Sidebar is no longer keyboard-navigable (click/keybind only) — only rail panes with
    # a j/k list need a count.
    %{
      Panel.Stack => length((state.stack || @empty_stack).commits),
      Panel.Memory => memory_section_count(state)
    }
  end

  defp memory_section_count(%{memory: nil}), do: 0
  defp memory_section_count(%{focus: %{section: 1}, memory: m}), do: length(m.habits)
  defp memory_section_count(%{memory: m}), do: length(m.pinned)

  # MAIN's detail for the focused pane's current selection, or nil (this pane has no detail, or
  # nothing is selected) → the terminal stays. Dispatch per pane; Commits resolves the selected
  # commit's diff via Console.Stack.show, Memory the selected pinned fact / pending habit.
  # An open /status readout wins — only reachable while focus.detail? (the reads gate), and any
  # pane Enter clears it first, so it can never shadow a pane's own detail.
  defp tlon_detail(%{status_detail: %{} = status}, _layout), do: status

  defp tlon_detail(state, layout) do
    case Focus.focused_pane(state.focus, layout) do
      Panel.Stack -> commit_detail(state, Focus.cursor(state.focus, layout))
      Panel.Memory -> memory_detail(state, Focus.cursor(state.focus, layout))
      _ -> nil
    end
  end

  @doc false
  # The /status detail's content, from the same read the footer condenses — Panel.Health's own
  # rows flattened to detail lines, so the two surfaces can't drift. Pure; exposed for tests.
  def status_detail_content(nil), do: %{title: "status", lines: [{"health probe hasn't run yet", :dim}]}

  def status_detail_content(health) do
    lines =
      health
      |> Panel.Health.render(%{x: 0, y: 0, w: 80, h: 100})
      |> Enum.map(fn row -> {Enum.map_join(row, fn {t, _style} -> t end), :normal} end)

    %{title: "status", lines: lines}
  end

  @doc false
  # The focused selection's clipboard text — pane dispatch mirrors tlon_detail/2. An open detail
  # wins (yank what's on screen). Exposed as the pure decision behind `apply_effect(:yank, ...)`,
  # testable without the tty write.
  def yank_text(%{focus: %Focus{detail?: true}} = state) do
    case tlon_detail(state, tlon_layout(state)) do
      %{title: title, lines: lines} -> {"detail", Enum.map_join([{title, nil} | lines], "\n", fn {t, _} -> t end)}
      _ -> nil
    end
  end

  def yank_text(state) do
    layout = tlon_layout(state)
    cursor = Focus.cursor(state.focus, layout)

    case Focus.focused_pane(state.focus, layout) do
      Panel.Stack -> Panel.Stack.yank(state.stack, cursor)
      Panel.Memory -> Panel.Memory.yank(memory_for_yank(state), cursor)
      _ -> nil
    end
  end

  defp memory_for_yank(%{memory: nil}), do: nil
  defp memory_for_yank(%{memory: memory, focus: focus}), do: Map.put(memory, :section, focus.section)

  # Section 0 (pinned) → the selected fact's full text + metadata; section 1 (habits) → the selected
  # habit's text + rationale. nil (empty section / no memory) leaves the terminal up.
  defp memory_detail(%{memory: nil}, _index), do: nil

  defp memory_detail(%{focus: %{section: 1}, memory: m}, index), do: habit_detail(Enum.at(m.habits, index))
  defp memory_detail(%{memory: m}, index), do: fact_detail(Enum.at(m.pinned, index))

  defp fact_detail(nil), do: nil

  defp fact_detail(fact) do
    meta =
      [{"kind: #{fact.kind}  ·  #{fact.provenance}", :dim}] ++
        for {label, val} <- [{"check", fact.check_cmd}, {"incident", fact.incident}, {"taught", fact.taught}],
            is_binary(val) and val != "",
            do: {"#{label}: #{val}", :dim}

    %{title: "FLOOR FACT", lines: [{"", :normal}, {fact.text, :normal}, {"", :normal} | meta]}
  end

  defp habit_detail(nil), do: nil

  defp habit_detail(habit) do
    by = if is_binary(habit.proposed_by), do: "  ·  proposed by #{habit.proposed_by}", else: ""

    rationale =
      if is_binary(habit.rationale) and habit.rationale != "", do: [{"", :normal}, {habit.rationale, :dim}], else: []

    %{title: "PENDING HABIT#{by}", lines: [{"", :normal}, {habit.text, :normal} | rationale]}
  end

  defp commit_detail(state, index) do
    case Enum.at((state.stack || @empty_stack).commits, index) do
      %{hash: hash, subject: subject} ->
        dir = workspace_repo_dir(active_workspace_id(state))
        %{title: "commit #{hash} · #{subject}", lines: Enum.map(Console.Stack.show(hash, dir), &diff_line/1)}

      nil ->
        nil
    end
  end

  defp diff_line(%{text: text, kind: kind}), do: {text, diff_style(kind)}
  defp diff_style(:add), do: :diff_add
  defp diff_style(:del), do: :diff_del
  defp diff_style(:hunk), do: :diff_hunk
  defp diff_style(:file), do: :label
  defp diff_style(:meta), do: :dim
  defp diff_style(:context), do: :normal

  # The active workspace's machine ROOT id (per-workspace re-scope, 2026-08-31) — the coworker
  # IDENTITY-spawn + standing-thread paths, which must land on a real thread. Prefers the
  # workspace's root; falls back to ANY open machine thread (a pre-bootstrap DB, the test harness's
  # cache-only workspaces). The CENTER stack + orchestrator post stay STRICT (no fallback), so they
  # never bleed another workspace's threads. nil only when there is no machine thread at all.
  defp machine_thread_id(workspace_id) do
    case Channel.machine_thread(workspace_id) || Channel.machine_thread() do
      %{id: id} -> id
      _ -> nil
    end
  end

  # Expire cached probes once @probe_ms has passed; render's ensure_probes refills lazily.
  defp maybe_expire_probes(state) do
    if System.monotonic_time(:millisecond) - state.probed_at >= @probe_ms do
      %{state | stack: nil, health: nil, memory: nil, leaves: nil, gates: nil}
    else
      state
    end
  end

  # Fill the probe cache when a Workspace space is active and the cache is cold. Elsewhere the probes
  # stay nil — git/nix/df/tmux forks and server reads are wasted on spaces that never show them.
  defp ensure_probes(%{active_key: key, stack: nil} = state) when Space.workspace?(key) do
    %{
      state
      | stack: stack_read(key),
        health: health_read(),
        memory: memory_read(key),
        gates: gates_read(key),
        ws_thread_ids: workspace_thread_id_set(key),
        probed_at: System.monotonic_time(:millisecond)
    }
  end

  # Orbis' survey only needs the rollup, not the git/nix/df battery — fill just the cached leaves
  # rollup on the SAME @probe_ms throttle so `orbis_workspaces/1` reads the cache, never gathers server
  # per-frame.
  defp ensure_probes(%{active_key: :orbis, leaves: nil} = state) do
    %{state | leaves: Console.Orbis.rollup(), probed_at: System.monotonic_time(:millisecond)}
  end

  defp ensure_probes(state), do: state

  # The Memory pane read: coverage stats + the always-loaded pinned set + the pending-habit queue.
  defp memory_read(workspace_id) do
    %{
      coverage: Server.recall_coverage(workspace_id),
      pinned: Server.pinned(workspace_id),
      habits: Server.pending_habits(workspace_id)
    }
  end

  # The NOW pane's ATTENTION read (Slice 4D): worklines parked awaiting the operator — the gates the
  # `approve N` verb clears. Best-effort; a server hiccup leaves the feed rather than crashing a frame.
  # The active workspace's thread ids as a MapSet (or nil on a server hiccup → unfiltered feed).
  defp workspace_thread_id_set(workspace_id) do
    MapSet.new(Server.workspace_thread_ids(workspace_id))
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Filter the global activity buffer to the active workspace: keep an event when its row has no
  # thread (a global event) or its thread is in the workspace. nil id-set = unfiltered (server down).
  defp scope_activity(activity, nil), do: activity

  defp scope_activity(activity, %MapSet{} = ids) do
    Enum.filter(activity, fn {_tag, row} ->
      case Map.get(row, :thread_id) do
        nil -> true
        tid -> MapSet.member?(ids, tid)
      end
    end)
  end

  defp gates_read(workspace_id) do
    workspace_id
    |> Server.workline_statuses()
    |> Enum.filter(&(&1.awaiting not in [nil, ""]))
    |> Enum.map(&Map.take(&1, [:id, :title, :stage, :awaiting]))
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # The STACK read: branch, dirty status, ahead/behind, status summary, enriched commits.
  # One ahead_behind call, destructured — it forks a git per call.
  defp stack_read(workspace_id) do
    dir = workspace_repo_dir(workspace_id)
    {ahead, behind} = Console.Stack.ahead_behind(dir)

    %{
      branch: Console.Stack.branch(dir),
      dirty: Console.Stack.dirty?(dir),
      ahead: ahead,
      behind: behind,
      status_summary: Console.Stack.status_summary(dir),
      commits: Console.Stack.commits(dir),
      files: Console.Stack.recent_files(dir),
      tools: Console.Stack.tools()
    }
  end

  # The git root the active workspace's STACK reads from: its primary repo path (each workspace
  # carries one), falling back to "." (the console's own checkout — the ficciones monorepo) when the
  # workspace has no real repo dir (e.g. a glob path like "modules/*", or a client dir that's absent).
  defp workspace_repo_dir(workspace_id) do
    case Server.repo_for_workspace(workspace_id) do
      {:ok, path} -> if File.dir?(path), do: path, else: "."
      _ -> "."
    end
  end

  # The HEALTH read. One nix_status call for gen+behind — nix-env --list-generations is the
  # single most expensive probe in the battery; calling it once matters.
  defp health_read do
    {nix_gen, nix_behind} = Console.Stack.nix_status()

    %{
      funes_up: Console.Stack.funes_up?(),
      tlon_up: Console.Stack.tlon_up?(),
      nix_gen: nix_gen,
      nix_behind: nix_behind,
      disk_pct: Console.Stack.disk_pct(),
      mem_pct: Console.Stack.mem_pct(),
      load_avg: Console.Stack.load_avg(),
      tools: Console.Stack.tools(),
      version: Console.Stack.release()
    }
  end

  # Advance a coworker's driver one step round the ring and persist it; returns the flash string.
  defp cycle_model!(profile_name) do
    current = Profiles.fetch(profile_name)
    next = Profiles.next_model(current && current.model)
    Console.Config.put_coworker_model(profile_name, next)
    "coworker driver → #{next.provider}/#{next.model} — applies on next spawn (console:reset)"
  end

  # The Orbis survey (Overview center): the per-WORKSPACE rollup grouping. Reads the cached
  # `state.leaves` rollup the @probe_ms throttle fills — its `workspaces` key. Empty list when server
  # is down / the cache is cold / there are no workspaces. Public: a pure read seam (unit-tested
  # against a known cache).
  def orbis_workspaces(state) do
    case state.leaves do
      %{workspaces: workspaces} -> workspaces
      _ -> []
    end
  end

  # TRIAGE reads: cross-thread blockers, failed checks, and unassigned threads.
  # Gathers from all open threads — a server Board aggregate.
  # Each section is `%{shown: [...], more: count}` so the panel can render "+N more".
  defp triage_read(threads) do
    scopes = for thread <- threads, do: {thread, Server.Board.brief(thread)}

    all_blockers =
      Enum.flat_map(scopes, fn {thread, scope} ->
        Enum.map(scope.blockers.shown, fn b -> %{thread_title: thread.title, summary: b.summary} end)
      end)

    all_failed_checks =
      Enum.flat_map(scopes, fn {thread, scope} ->
        scope.checks.shown
        |> Enum.filter(fn c -> c.kind == "check_failed" end)
        |> Enum.map(fn c -> %{thread_title: thread.title, cmd: cmd_from_detail(c.detail)} end)
      end)

    unassigned =
      threads
      |> Enum.filter(fn thread -> is_nil(thread.agent_id) end)
      |> Enum.map(fn thread -> %{title: thread.title} end)
      |> Enum.take(5)

    %{
      blockers: cap(all_blockers, 5),
      failed_checks: cap(all_failed_checks, 5),
      unassigned: unassigned
    }
  end

  defp cap(list, n), do: %{shown: Enum.take(list, n), more: max(length(list) - n, 0)}

  defp cmd_from_detail(%{"cmd" => cmd}), do: cmd
  defp cmd_from_detail(_), do: "check"

  # The Workspace's cast, spawned lazily on entry from its roster (C2.3 — replaces the old hardcoded
  # ensure_machine_coworker/ensure_claude_coworker/ensure_third_coworker trio): head = the CENTER
  # (embedded terminal, `new-session`), tail = tmux windows (`new-window`), each launcher chosen by
  # its archetype's harness. An empty roster / server-down space is a no-op. `spaces` defaults to the
  # live cache (`Space.all/0`, `render`'s call) but is overridable — mirrors `Space.fetch/1` vs
  # `/2` — so a test drives a roster without a live workspace in the server DB.
  @doc false
  def ensure_workspace_roster(state, spaces \\ Space.all())

  def ensure_workspace_roster(%{active_key: key} = state, spaces) when Space.workspace?(key) do
    case Space.fetch(key, spaces) do
      %Space{roster: [lead | rest]} -> state |> ensure_center(key, lead) |> ensure_windows(key, rest)
      _ -> state
    end
  end

  def ensure_workspace_roster(state, _spaces), do: state

  # The roster LEAD: a pi session working ON the box on a persistent "machine" thread (so its work
  # is triageable) — pi by design, claude stays the deliberate escalation (AGENTS.md routing).
  # Find-or-spawned here (render's stateful preamble), with a backoff: a failed spawn must not retry
  # the whole materialise+tmux pipeline on EVERY render — that would be a spawn storm whenever the
  # coworker can't start.
  defp ensure_center(state, workspace_id, lead) do
    now = System.monotonic_time(:millisecond)

    cond do
      is_pid(safe_terminal(:machine)) ->
        state

      not machine_spawn_due?(state.machine_retry_at, now) ->
        state

      true ->
        case spawn_center(workspace_id, lead) do
          pid when is_pid(pid) ->
            # Harnesses inside the center can emit kitty graphics themselves — tmux must pass the
            # APC through instead of eating it (design 2026-08-23 §Images rider).
            _ = tlon_run(workspace_id, ["set-option", "-g", "allow-passthrough", "on"])
            capture_standing_thread_id(state)

          _ ->
            %{state | machine_retry_at: now + @machine_spawn_backoff_ms}
        end
    end
  end

  # Stash the standing coworker's machine thread id, once, at its first successful spawn —
  # the id `ensure_thread_sessions` excludes from its own spawn pass (the standing center
  # coworker is not "a staffed machine thread it should spawn a session for", it already has one).
  defp capture_standing_thread_id(%{standing_thread_id: nil} = state),
    do: %{state | standing_thread_id: machine_thread_id(active_workspace_id(state))}

  defp capture_standing_thread_id(state), do: state

  # The roster TAIL: one tmux window per entry, each a second window in the SAME session as the
  # center, joined to the SAME root thread, so the cast coordinates over server messages like any
  # two agents. Gated on the center up (its spawn opens/finds the root thread these join) and on
  # the window not already being there (tmux `new-window` isn't idempotent like `new-session -A` —
  # a naive re-run every render would spawn a fresh coworker every tick).
  defp ensure_windows(state, workspace_id, entries) do
    if is_pid(safe_terminal(:machine)) do
      existing = workspace_id |> tlon_tabs() |> MapSet.new(& &1.name)

      entries
      |> Enum.map(&Profiles.roster_entry/1)
      |> Enum.reject(&MapSet.member?(existing, &1.name))
      |> Enum.each(fn %{archetype: arch, name: name} ->
        spawn_window(workspace_id, Profiles.instantiate(%{archetype: arch, name: name}))
      end)
    end

    state
  end

  # A tail window's launcher comes from its profile's HARNESS DRIVER (Slice D) — real Claude
  # (honestly identified, no pi-multi-account impersonation — see Console.Profiles' @seed_roster
  # comment) or a windowed pi; the spawn plumbing is shared. Materialised first: both drivers
  # read the profile's config dir (pi: the whole dir; claude: system_prompt.md as the role).
  defp spawn_window(workspace_id, %Profile{name: name} = profile) do
    _ = materialise_profile(profile)
    command = Harness.driver(profile.harness).launch_command(profile)
    spawn_harness_window(workspace_id, "#{name}-machine", name, machine_thread_id(workspace_id), command)
  end

  # A staffed-but-session-less machine thread gets its own tmux window (`t<id>`), so a
  # thread the operator opened outside the standing coworkers gets a live coworker
  # working IT specifically, not just accumulating unread messages. Two-phase, like the coworker
  # windows: `new-window` first (this pass), the opening turn only injected on a LATER render once
  # the window shows up live in `tlon_tabs()` — send-keys the instant `new-window` returns races
  # the harness's own boot and the first turn lands on the floor.
  #
  # EVERY worker roster lead gets a leaf window — claude AND pi harness, dispatched by the lead's
  # profile (per-thread-agents Slice A; the old `claude_launched?` gate left a pi lead's turns
  # landing in the ONE standing pi's context — the isolation bug). A meta (surveyor) or
  # roster-unknown lead gets none.
  #
  # Public seam (@doc false) so the suite drives the real dispatch through `:tlon_cmd`/`:tlon_join`
  # with injected `spaces`, mirroring `ensure_workspace_roster/2`.
  @doc false
  def ensure_thread_sessions(state, spaces \\ Space.all())

  def ensure_thread_sessions(%{active_key: key} = state, spaces) when Space.workspace?(key) do
    tabs = tlon_tabs(key)
    now = System.monotonic_time(:millisecond)
    roster = space_roster(key, spaces)
    threads = Server.staffed_machine_threads()
    # Window names spawned THIS pass join the taken set, so two new leaves with the same title in
    # one render can't collide on a name (the tag targets by name once, right after new-window).
    taken = MapSet.new(tabs, & &1.name)
    # The leaf-cap budget (Config.max_leaves): seats left after the already-live leaves. A thread
    # past the cap stays open/staffed and just waits — a later pass staffs it once a seat frees.
    budget = Console.Config.max_leaves() - Enum.count(tabs, &leaf_window?/1)

    {state, _taken, _budget} =
      Enum.reduce(threads, {state, taken, budget}, fn thread, {st, tk, bg} ->
        ensure_thread_session(key, roster, thread, tabs, now, st, tk, bg)
      end)

    sweep_orphan_leaves(key, tabs, MapSet.new(threads, & &1.id))
    state
  end

  def ensure_thread_sessions(state, _spaces), do: state

  # Is this tab a LEAF session (vs the center/tail/console windows)? The `@funes_thread` tag, or
  # the legacy `t<id>` name.
  defp leaf_window?(%{thread_id: tid}) when is_integer(tid), do: true
  defp leaf_window?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)

  # Convergent teardown: a leaf window whose thread is no longer open+staffed — closed while
  # console was down, or wholesale-cleared — dies here, not only on the `:thread_closed` Bus event
  # the cockpit may never have seen. Matches ONLY leaf windows (the `@funes_thread` tag, or the
  # legacy `t<id>` name); the center/tail/console windows are never candidates. Runs off the same
  # tabs snapshot as the spawn pass, so a leaf spawned this pass (absent from the snapshot) can't
  # be swept.
  defp sweep_orphan_leaves(workspace_id, tabs, live_ids) do
    for tab <- tabs, orphan_leaf?(tab, live_ids) do
      tlon_run(workspace_id, ["kill-window", "-t", "#{workspace_session(workspace_id)}:#{tab.index}"])
    end

    :ok
  end

  defp orphan_leaf?(%{thread_id: tid}, live_ids) when is_integer(tid), do: not MapSet.member?(live_ids, tid)

  defp orphan_leaf?(%{name: name}, live_ids) do
    case Regex.run(~r/\At(\d+)\z/, name) do
      [_, id] -> not MapSet.member?(live_ids, String.to_integer(id))
      nil -> false
    end
  end

  defp ensure_thread_session(workspace_id, roster, %{id: id, lead: lead, title: title}, tabs, now, state, taken, budget) do
    cond do
      # The standing coworker's own thread — it already has a session (the center window),
      # just not a leaf one. Never spawn a duplicate for it.
      id == state.standing_thread_id ->
        {state, taken, budget}

      leaf_tab(tabs, id) ->
        {maybe_inject_opening_turn(workspace_id, id, tabs, now, state), taken, budget}

      not thread_spawn_due?(state.thread_spawn_retry[id], now) ->
        {state, taken, budget}

      budget <= 0 ->
        {note_parked(state, id), taken, budget}

      true ->
        spawn_leaf(workspace_id, roster, lead, title, id, now, state, taken, budget)
    end
  end

  # Tell the thread ONCE why nobody is working it yet — a silently parked leaf reads exactly like
  # the old silence bug. Best-effort; the note is informational, the parking is the budget check.
  defp note_parked(state, id) do
    if MapSet.member?(state.parked_noted, id) do
      state
    else
      _ =
        try do
          Channel.post(%{
            thread_id: id,
            author: "console",
            body:
              "⏸ parked — the leaf cap (#{Console.Config.max_leaves()}) is reached. This thread keeps its lead " <>
                "and starts automatically when a seat frees (close an idle leaf, or raise \"max_leaves\")."
          })
        rescue
          _ -> :ok
        catch
          :exit, _ -> :ok
        end

      %{state | parked_noted: MapSet.put(state.parked_noted, id)}
    end
  end

  # Spawn a leaf via the lead's roster profile: the harness DRIVER supplies the exec (Slice D),
  # the shared plumbing joins the leaf's OWN thread id so `TLON_THREAD` binds the harness to the
  # thread it works. nil profile (meta/unknown lead) spawns nothing. The window gets a HUMAN name
  # (`<archetype>-<title-slug>`, Slice C); the routing key is the `@funes_thread` option
  # `tag_leaf/4` stamps right after the spawn.
  defp spawn_leaf(workspace_id, roster, lead, title, id, now, state, taken, budget) do
    case Profiles.leaf_profile(lead, roster) do
      nil ->
        {state, taken, budget}

      %Profile{} = profile ->
        _ = materialise_profile(profile)
        window = LeafWindow.name(profile.archetype, title, taken)
        command = Harness.driver(profile.harness).launch_command(profile)
        result = spawn_harness_window(workspace_id, lead, window, id, command)
        state = record_thread_spawn(tag_leaf(result, workspace_id, window, id), state, id, now)
        # A parked thread that finally got its seat may park again later; let it re-note then.
        state = %{state | parked_noted: MapSet.delete(state.parked_noted, id)}

        {state, MapSet.put(taken, window), budget - 1}
    end
  end

  # Stamp the routing key on a just-spawned leaf window: `@funes_thread <id>`. From here on the
  # window name is cosmetic — delivery/attach resolve thread → window via this option (`leaf_tab`).
  # Name-targeted exact-match (`=`); safe because the name was minted collision-free against this
  # pass's taken set. Only a successful spawn tags; a failed one just backs off.
  defp tag_leaf({_out, 0} = ok, workspace_id, window, id) do
    session = workspace_session(workspace_id)
    _ = tlon_run(workspace_id, ["set-option", "-w", "-t", "#{session}:=#{window}", "@funes_thread", "#{id}"])
    ok
  end

  defp tag_leaf(other, _workspace_id, _window, _id), do: other

  defp record_thread_spawn({_out, 0}, state, id, _now),
    do: %{state | thread_spawn_retry: Map.delete(state.thread_spawn_retry, id)}

  defp record_thread_spawn(_result, state, id, now),
    do: %{state | thread_spawn_retry: Map.put(state.thread_spawn_retry, id, now + @thread_spawn_backoff_ms)}

  # Is a per-thread session spawn attempt due? Mirrors `machine_spawn_due?/2` — nil means "no
  # backoff pending, try now".
  defp thread_spawn_due?(nil, _now), do: true
  defp thread_spawn_due?(retry_at, now), do: now >= retry_at

  # Does the cockpit staff a per-thread leaf window for this lead? Any WORKER roster handle
  # (claude or pi harness) qualifies — the predicate `delivery_target` and the spawn pass share,
  # so routing and spawning can never disagree about who owns a thread's turns.
  defp leaf_staffed?(lead, workspace_id), do: lead in Profiles.leaf_handles(active_roster(workspace_id))

  # This Workspace's roster (`Console.Mention.route/3`'s resolution fixture) — server-down / no roster
  # degrades to `[]` (nobody resolves, nobody wakes).
  defp active_roster(workspace_id) do
    case Space.fetch(workspace_id) do
      %Space{roster: roster} -> roster
      _ -> []
    end
  end

  # Same read against an injected spaces list (the `ensure_thread_sessions/2` test seam).
  defp space_roster(workspace_id, spaces) do
    case Space.fetch(workspace_id, spaces) do
      %Space{roster: roster} -> roster
      _ -> []
    end
  end

  # Two-phase, so a just-booted leaf window submits its opening turn instead of leaving it typed
  # but unsent: stage 1 types the text; stage 2, once the text has settled for
  # @opening_submit_delay_ms, sends Enter. The PHASE lives in tmux itself (`@funes_opening`
  # "typed"/"done" on the window) so a cockpit restart mid-phase can't re-type the opening into a
  # live session or (done-tagged) re-send it — process state only carries the settle timestamp; a
  # "typed" tag with no timestamp (restart) means the text settled long ago, submit now.
  defp maybe_inject_opening_turn(workspace_id, id, tabs, now, state) do
    tab = leaf_tab(tabs, id)

    cond do
      is_nil(tab) ->
        state

      tab.opening == "done" or MapSet.member?(state.opening_injected, id) ->
        mark_opening_done(state, id)

      tab.opening == "typed" or Map.has_key?(state.opening_text_at, id) ->
        submit_opening(workspace_id, id, tab, now, state)

      true ->
        inject_opening_text(workspace_id, id, tab)
        tag_opening(workspace_id, tab.index, "typed")
        %{state | opening_text_at: Map.put(state.opening_text_at, id, now)}
    end
  end

  defp submit_opening(workspace_id, id, tab, now, state) do
    typed_at = state.opening_text_at[id]

    if is_nil(typed_at) or now - typed_at >= @opening_submit_delay_ms do
      submit_turn(workspace_id, tab.index)
      tag_opening(workspace_id, tab.index, "done")
      mark_opening_done(state, id)
    else
      state
    end
  end

  defp mark_opening_done(state, id) do
    %{
      state
      | opening_injected: MapSet.put(state.opening_injected, id),
        opening_text_at: Map.delete(state.opening_text_at, id)
    }
  end

  # Stamp the opening phase on the window itself — index-targeted, best-effort.
  defp tag_opening(workspace_id, index, phase) do
    _ =
      tlon_run(workspace_id, [
        "set-option",
        "-w",
        "-t",
        "#{workspace_session(workspace_id)}:#{index}",
        "@funes_opening",
        phase
      ])

    :ok
  end

  # Type the thread's latest operator message into its just-appeared leaf window (no Enter yet —
  # stage 2 submits). Best-effort: a thread with no operator message yet is silently skipped —
  # never a render crash.
  defp inject_opening_text(workspace_id, id, %{index: index}) do
    message = Server.latest_operator_message(id)

    if message do
      operator = Application.get_env(:server, :operator, "andrew")
      inject_text(workspace_id, index, "[server thread ##{id}] #{operator}: #{one_line(message.body)}")
    end

    :ok
  end

  defp one_line(body), do: String.replace(body || "", "\n", " ")

  # A thread title from its opening message — first line, trimmed to a glanceable length.
  defp thread_title(text) do
    text |> String.split("\n", parts: 2) |> List.first() |> String.trim() |> String.slice(0, 60)
  end

  # `tmux new-window`, not Sessions.spawn_harness: a roster tail entry rides as a window of the
  # ALREADY-embedded tlon tmux session (the center is window 0), not a separate Console.Terminal/PTY
  # of its own. Fire-and-forget: a failed spawn (server down, no thread yet) just leaves the window
  # absent, and `ensure_windows` retries it on the next render — no backoff needed, `new-window` is
  # cheap and idempotent-by-absence-check above.

  # Open a harness window named `window` on `thread_id` as server handle `handle`, running
  # `command` (the profile's `Console.Harness.Driver.launch_command/1`) in workspace `workspace_id`. The
  # roster tail windows AND the per-thread leaf windows all ride this ONE spawn: identity join +
  # tmux plumbing are harness-agnostic (Slice D); only the exec differs, and that came from the
  # driver. `TLON_THREAD` binds the harness to the thread it's actually meant to work on.
  defp spawn_harness_window(workspace_id, handle, window, thread_id, command) do
    with id when is_integer(id) <- thread_id,
         {:ok, %{exports: exports}} <- joiner().(id, handle, mandate: "machine") do
      script = "export TERM=xterm-256color\n" <> exports <> "\nexec " <> command
      # `-d`: spawn the window in the background — a coworker starting must NOT yank the operator
      # off whatever window they're on.
      tlon_run(workspace_id, ["new-window", "-d", "-t", workspace_session(workspace_id), "-n", window, script])
    end
  end

  # The identity minter for a tail-window spawn — defaults to the live server join (mints in-node
  # against the Repo/tokens), overridable via `:console, :tlon_join` so a test drives `ensure_windows`
  # against the SAME injected `:tlon_cmd` tmux runner without a live DB (mirrors `Console.Crew`'s
  # `:crew_join`/`:crew_cmd` pair).
  defp joiner, do: Application.get_env(:console, :tlon_join, &Spawn.join/3)

  @doc false
  # Is a machine-coworker spawn attempt due? `machine_retry_at` is nil until an attempt FAILS (the
  # "no backoff pending" sentinel — try now), then a future monotonic timestamp for @machine_spawn_backoff_ms.
  # It MUST be nil, not 0: BEAM monotonic time starts large-NEGATIVE, so `now < 0` reads as "still
  # backing off" forever and the coworker never spawns.
  def machine_spawn_due?(nil = _retry_at, _now), do: true
  def machine_spawn_due?(retry_at, now), do: now >= retry_at

  # Materialise the Workspace's LEAD roster entry into a profile, find-or-create the machine identity,
  # then spawn the center: an embedded tmux client attached to the standing session (pi as window 0
  # if absent) — an console restart re-attaches to the running pi instead of spawning another.
  defp spawn_center(workspace_id, lead) do
    %{archetype: arch, name: name} = Profiles.roster_entry(lead)

    with %Profile{} = profile <- Profiles.instantiate(%{archetype: arch, name: name}),
         {:ok, _dir} <- materialise_profile(profile),
         {:ok, exports} <- machine_exports(workspace_id, "#{name}-machine"),
         # kitty: false — tmux wants its Ctrl+B prefix as legacy \x02, not CSI-u (see Terminal.init).
         {:ok, pid} <-
           safe_spawn_harness(:machine, exports, launcher: profile_launcher(workspace_id, name, profile), kitty: false) do
      pid
    else
      _error -> nil
    end
  end

  # Wrap the raising materialiser so a filesystem hiccup degrades to "no coworker", never a cockpit crash.
  defp materialise_profile(profile) do
    {:ok, Profiles.materialise!(profile)}
  rescue
    e -> {:error, e}
  end

  # The bare `pi` invocation for a profile — moved to the pi harness driver (Slice D); kept as a
  # delegator for `profile_launcher` (the center's new-session) and `Console.Crew`.
  @doc false
  def pi_command(%Profile{} = profile), do: Harness.Pi.launch_command(profile)

  # The center coworker's launcher: pi on its OWN tmux server (`-L console-workspace-<id>`, id-derived —
  # not name-derived, so a workspace rename can't orphan it — + the profile's persistence-free
  # tmux.conf), window 0 named `lead_name` (the roster lead's name — the tab-strip label).
  # ADAPTERS_RELOAD_CMD lets adapters/reload respawn in place with --continue, keeping the thread across
  # the restart.
  def profile_launcher(workspace_id, lead_name, %Profile{} = profile) do
    pi = pi_command(profile)
    dir = Profiles.config_dir(profile.name)
    reload_cmd = {"ADAPTERS_RELOAD_CMD", pi <> " --continue"}
    env_flags = Enum.map_join([reload_cmd], " ", fn {k, v} -> "-e #{sh_single_quote(k <> "=" <> v)}" end)

    "tmux -L #{workspace_socket(workspace_id)} -f #{Path.join(dir, "tmux.conf")}" <>
      " new-session -A -s #{workspace_session(workspace_id)} -n #{lead_name} #{funes_identity_flags()} #{env_flags} '#{pi}'"
  end

  @doc false
  # `-e TLON_X="$TLON_X"` for each identity var. The Tlön pi's MCP wiring reads `${TLON_MCP_URL}`
  # (profile mcp.json) and mints a bearer for TLON_THREAD/TLON_AUTHOR — but spawn_harness only
  # `export`s those in pi's ONE-SHOT launch shell, so they live in pi's PROCESS env alone. A
  # continuum/`--continue` restore, a `respawn-pane`, or a reload in a clean shell then boots with
  # `${TLON_MCP_URL}` empty → the server server never registers ("Tool not found", never the 404 the
  # adapter self-heals). Putting them in the tmux SESSION env via `-e` makes the identity durable
  # across respawns; `-e` also refreshes on `new-session -A`, so an console restart re-freshes a stale
  # identity instead of stranding it. bash sourced the exports first, so it expands the values here
  # into the current literal ones.
  def funes_identity_flags do
    Enum.map_join(@funes_identity_env, " ", fn var -> ~s(-e #{var}="$#{var}") end)
  end

  # POSIX single-quote: escape embedded quotes as '\'' so the value survives the shell verbatim.
  defp sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  # A Workspace's tmux session/socket, id-derived (rename-proof) — replaces the old singleton "tlon"
  # session on the lead-name-derived "console-<coworker>" socket. Two workspaces can never collide on
  # either name, and a workspace rename can't orphan a running session.
  defp workspace_session(id), do: "w#{id}"
  defp workspace_socket(id), do: "console-workspace-#{id}"

  # A Workspace's windows as tabs — console draws them itself (tmux's own status bar is off), so it asks
  # tmux for the live truth rather than tracking cockpit state (can't drift). Best-effort: the
  # session not being up yet is an empty strip, not a crash.
  defp tlon_tabs(workspace_id) do
    args = [
      "list-windows",
      "-t",
      workspace_session(workspace_id),
      "-F",
      "\#{window_active}\t\#{window_index}\t\#{window_name}\t\#{@funes_thread}\t\#{@funes_opening}\t\#{window_activity}"
    ]

    case tlon_run(workspace_id, args) do
      {out, 0} -> parse_tlon_tabs(out)
      _ -> []
    end
  end

  # Every Workspace tmux call — queries, re-points, AND the send-keys injects — routes through here:
  # one seam over the coworker's private server, so a test can inject a fake runner
  # (`:console, :tlon_cmd`) and assert argv without a live tmux.
  # No workspace id (server genuinely down — the fallback Workspace is gone, reshape slice A): there is
  # no coworker server to target, and dropping the `-L` flag would aim kill-window/send-keys at
  # the user's PERSONAL tmux server. No-op with a nonzero "exit" so callers read it as a miss.
  defp tlon_run(nil, _args), do: {"no active workspace", 1}

  defp tlon_run(workspace_id, args) do
    runner = Application.get_env(:console, :tlon_cmd, &System.cmd/3)
    runner.("tmux", tlon_tmux(workspace_id, args), stderr_to_stdout: true)
  end

  # Every tmux call about a Workspace's coworker targets ITS private server (`-L console-workspace-<id>`),
  # never the user's default one.
  defp tlon_tmux(workspace_id, args), do: ["-L", workspace_socket(workspace_id)] ++ args

  @doc false
  # `window_active` is "1" for the current window, "0" otherwise; each line is
  # `<active>\t<index>\t<name>\t<@funes_thread>\t<@funes_opening>\t<window_activity>` — the index
  # is tmux's window index (select-window on a tab click); `@funes_thread` is the leaf routing key
  # stamped at spawn (Slice C — empty for non-leaf windows, parsed to nil); `@funes_opening` is the
  # two-phase opening-turn state ("typed"/"done") persisted in tmux so a cockpit restart never
  # re-types a live leaf's opening; `window_activity` is the last-content-change unix timestamp
  # `Console.Presence` infers "working" from. Shorter lines (older fakes/format) still parse,
  # missing fields nil.
  def parse_tlon_tabs(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 6) do
        [active, index, name | rest] when rest != [] or name != "" ->
          [thread, opening, activity] =
            case rest do
              [t, o, a] -> [t, o, a]
              [t, o] -> [t, o, ""]
              [t] -> [t, "", ""]
              [] -> ["", "", ""]
            end

          [
            %{
              name: name,
              active?: active == "1",
              index: index,
              thread_id: int_or_nil(thread),
              opening: if(opening in ["typed", "done"], do: opening),
              activity: int_or_nil(activity)
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp int_or_nil(s) do
    case Integer.parse(s) do
      {id, ""} -> id
      _ -> nil
    end
  end

  # The tab running thread `id`'s leaf session: the `@funes_thread`-stamped window (Slice C), else
  # the legacy `t<id>`-named one (a live pre-C window) — nil when the leaf has no window yet.
  # Routing resolves thread → window HERE, never by parsing a (now human-named) window name.
  defp leaf_tab(tabs, id), do: Enum.find(tabs, &(&1.thread_id == id)) || Enum.find(tabs, &(&1.name == "t#{id}"))

  # Resolve a machine pane's TLON_* exports by find-or-create: reuse the latest open machine
  # thread (joining it as `agent`) if one exists, else open a fresh `scope: "machine"` thread.
  defp machine_exports(workspace_id, agent) do
    # Prefer the active workspace's root; else reuse ANY open machine thread (a pre-bootstrap DB, or
    # the test harness's cache-only workspaces) rather than proliferating a fresh one.
    case Channel.machine_thread(workspace_id) || Channel.machine_thread() do
      %{id: id} ->
        with {:ok, %{exports: e}} <- Spawn.join(id, agent), do: {:ok, e}

      nil ->
        with {:ok, %{exports: e}} <- Spawn.env("general", agent, mandate: "machine", scope: "machine"), do: {:ok, e}
    end
  end

  # Keep the center session's PTY sized to the center region so it reflows with the window. Sized to
  # the EXACT center Terminal rect (Console.View.center_rect — the one layout authority), so the PTY
  # matches what's on screen; the terminal reflows on every window resize.
  defp resize_focused_terminal(state) do
    with term when is_pid(term) <- center_terminal(state) do
      {cols, rows} = center_dims(state)
      Terminal.resize(term, cols, rows)
    end
  end

  # Size the PTY to EXACTLY the center Terminal's content rect (Console.View.center_rect), so pi never
  # draws past the frame (a wider PTY spills; a shorter one leaves a dead band). The tertius band
  # already shrinks that rect (its own section, not the terminal's), so no separate reserve is needed.
  defp center_dims(%{active_key: active_key, w: w, h: h}) do
    rect = View.center_rect(active_key, w, h)
    {max(rect.w, 1), max(rect.h, 1)}
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
  # crash in any callback — the reason init traps exits.
  defp quit(state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, state), do: teardown(state)

  defp teardown(state) do
    # Best-effort: clear any placed images before the alt screen goes away. Straight to /dev/tty
    # like the Kitty pop below (the io server may already be winding down on a crash), and a
    # failure here must never skip the tty restore (a wedged shell is worse than a stray image).
    try do
      if Console.Graphics.kitty?(), do: File.write("/dev/tty", Console.Graphics.delete_all())
    catch
      _, _ -> :ok
    end

    # Pop Kitty while still ON the alt screen (the spec gives main and alternate screens
    # INDEPENDENT keyboard-flag stacks, so the pop must land on the screen the push landed on).
    # Straight to /dev/tty, not stdout — the io server may already be winding down on a crash.
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable)

    # Each step in its own try: a wedged Driver stop (it can exceed its 500ms) must never skip
    # tb_shutdown — that skip leaves the shell in alt-screen + mouse-reporting, needing `reset`.
    try do
      if is_pid(state.driver) and Process.alive?(state.driver),
        do: GenServer.stop(state.driver, :normal, 500)
    catch
      _, _ -> :ok
    end

    try do
      :termbox2_nif.tb_shutdown()
    catch
      _, _ -> :ok
    end

    # Back on the MAIN screen now — final belt-and-braces restore (see restore_host_tty/0).
    restore_host_tty()
  end

  # Force-disarm everything a dead cockpit could have left armed: Kitty pop (no-op on an empty
  # stack), mouse reporting off, leave alt screen, show cursor. Idempotent — run/0 also calls this
  # after a DOWN, so even a killed GenServer leaves a working shell, not `;5u` keystroke garbage.
  defp restore_host_tty do
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable <> "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h")
    :ok
  end

  @doc false
  # A formatted crash report for a non-normal DOWN reason, or nil for a clean quit — so a normal
  # operator quit doesn't spam the log. Pure; the IO is in log_crash/1.
  @spec crash_report(term()) :: String.t() | nil
  def crash_report(reason) when reason in [:normal, :shutdown], do: nil
  def crash_report({:shutdown, _}), do: nil
  def crash_report(reason), do: Exception.format_exit(reason)

  # Append a crashed exit to the crash log and echo it to stderr after the tty is restored, so it
  # doesn't get swallowed by the alt-screen. Best-effort: a log write failure never masks the crash.
  defp log_crash(reason) do
    case crash_report(reason) do
      nil ->
        :ok

      report ->
        Console.CrashLog.append("console crash", report)
        IO.puts(:stderr, "console crashed (logged to #{Console.CrashLog.path()}):\n#{report}")
        file_crash_issue(report)
    end
  rescue
    _ -> :ok
  end

  @doc false
  @spec crash_summary(String.t()) :: String.t()
  def crash_summary(report) do
    report |> String.split("\n", trim: true) |> List.first("a cockpit crash") |> String.slice(0, 120)
  end

  # A crashed cockpit files a server issue on the machine thread — its own failures become tracked,
  # triageable work in the system it renders, not just a log line. Deduped against the thread's open
  # issues so a crash loop files one, not a hundred. Best-effort: no server (down, or the crash took
  # it too) just means the crash log is the only record.
  defp file_crash_issue(report) do
    summary = "console crashed: " <> crash_summary(report)

    with %{id: id} = thread <- Channel.machine_thread(),
         false <- crash_issue_open?(Dossier.open_issues_for_thread(thread), summary) do
      Dossier.raise_issue(%{thread_id: id, summary: summary, evidence: report, found_by: "console"})
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @doc false
  # Dedupe against the thread's open issues. open_issues_for_thread returns the capped
  # `%{shown, more}` shape, NOT a bare list — enumerating the map raised here, the rescue above
  # swallowed it, and a crashed cockpit silently never filed its issue. Public + tested so the
  # shape contract can't silently regress again.
  @spec crash_issue_open?(%{shown: [map()]}, String.t()) :: boolean()
  def crash_issue_open?(%{shown: shown}, summary), do: Enum.any?(shown, &(&1.summary == summary))
end
