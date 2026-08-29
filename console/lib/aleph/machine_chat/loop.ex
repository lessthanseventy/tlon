defmodule Console.MachineChat.Loop do
  @moduledoc """
  The termbox host loop for the Tlön machine-chat tab (`general`) — Slack-shaped since the 2026-08
  reshape: a one-row header (workspace · thread/working counts · the ORBIS rollup), a left THREADS
  rail, ONE open conversation in the center with its composer underneath, and a right CREW rail
  showing the coworker pool with live working/typing indicators (tmux window activity). Pure
  logical state lives in `Console.MachineChat.Host`; geometry in `Layout`; the rails render in
  `Rail`/`Crew`; presence derives in `Presence`. This module owns the TTY, the poll timer, the
  center scroll, and the tmux/db edges. Not unit-tested — it grabs the TTY (aleph's law: test the
  pure seams, run the loop live).

  It's a READER for the feed (polls `Server.Channel.machine_threads/1` off the shared `TLON_DB`,
  since the node-local `Server.Bus` isn't reachable cross-process) but a WRITER for the composer:
  it posts as the operator straight through `Channel`, and wakes coworkers itself by tmux
  send-keys (the pure `Console.Mention` routing) — the cockpit only wakes agents for messages on
  ITS own bus, which it never sees from here.

  MODELESS input (the Slack model — no compose/browse split):
    * printable keys type into the composer; `Enter` sends — a REPLY into the open thread, or a
      NEW task thread after `Ctrl+N` (`Esc` cancels back to reply; `Ctrl+U` clears the draft —
      nothing else ever eats it).
    * `↑/↓` move the thread selection in the rail (the center follows); unread badges clear as
      you land on a thread.
    * wheel / PgUp / PgDn / Home / End scroll the open conversation; scrolling to the bottom
      resumes tail-follow.
  """
  use GenServer

  import Console.Panel, only: [blank: 0]

  alias Console.Board
  alias Console.Config
  alias Console.MachineChat.Host
  alias Console.MachineChat.Layout
  alias Console.MachineChat.Rail
  alias Console.MachineChat.Staffing
  alias Console.Mention
  alias Console.Panel
  alias Console.Panel.Crew
  alias Console.Presence
  alias Console.Profiles
  alias Console.Transcript
  alias Raxol.Core.Events.Event
  alias Server.Channel

  @poll_ms 700
  @render_coalesce_ms 8
  @tb_output_truecolor 5
  @tb_input_esc_mouse 5
  @wheel_lines 3

  @restore "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h"

  @doc "Start the tab and block until the operator quits — the entry point the Mix task calls."
  @spec run() :: :ok
  def run do
    case GenServer.start(__MODULE__, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> restore_host_tty()
        end

      {:error, {:tb_init_failed, code}} ->
        IO.puts(:stderr, "machine-chat needs a real terminal (tb_init returned #{code}) — run it in a tmux pane.")

      {:error, reason} ->
        IO.puts(:stderr, "machine-chat failed to start: #{inspect(reason)}")
    end
  end

  @impl true
  def init(_opts) do
    case :termbox2_nif.tb_init() do
      0 ->
        Process.flag(:trap_exit, true)
        :termbox2_nif.tb_set_output_mode(@tb_output_truecolor)
        :termbox2_nif.tb_set_input_mode(@tb_input_esc_mouse)
        normalize_cursor_keys()
        {:ok, driver} = Raxol.Terminal.Driver.start_link(dispatcher_pid: self())

        state = %{
          driver: driver,
          w: max(:termbox2_nif.tb_width(), 1),
          h: max(:termbox2_nif.tb_height(), 1),
          view: Host.new(),
          scroll: 0,
          max_scroll: 0,
          follow?: true,
          render_armed?: false,
          rollup: nil,
          windows: [],
          leads: %{},
          roster: [],
          root_id: nil,
          pending_delete: nil,
          now_s: System.os_time(:second)
        }

        send(self(), :poll)
        {:ok, paint(state)}

      other ->
        {:stop, {:tb_init_failed, other}}
    end
  end

  # termbox2's tb_init enables DECCKM; reset on /dev/tty so arrows arrive as CSI, not SS3.
  defp normalize_cursor_keys do
    _ = File.write("/dev/tty", "\e[?1l")
    :ok
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_ms)
    {:noreply, schedule_render(poll_refresh(state))}
  end

  def handle_info(:render, %{render_armed?: false} = state), do: {:noreply, state}
  def handle_info(:render, state), do: {:noreply, paint(%{state | render_armed?: false})}
  def handle_info({:EXIT, pid, reason}, %{driver: pid} = state), do: {:stop, reason, state}
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast({:dispatch, %Event{type: :resize}}, state), do: {:noreply, schedule_render(refresh_size(state))}

  def handle_cast({:dispatch, %Event{type: :key, data: key}}, state), do: handle_key(key, state)

  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_up}}}, state),
    do: {:noreply, scroll_by(state, -@wheel_lines)}

  def handle_cast({:dispatch, %Event{type: :mouse, data: %{button: :wheel_down}}}, state),
    do: {:noreply, scroll_by(state, @wheel_lines)}

  def handle_cast({:dispatch, _event}, state), do: {:noreply, state}

  # MODELESS: the composer takes printables, the rail takes arrows, the center takes paging.
  # A delete refusal notice is transient — the next keypress of any kind clears it.
  defp handle_key(key, %{pending_delete: {:refused, _}} = state), do: handle_key(key, %{state | pending_delete: nil})

  # Ctrl+D on the rail-selected thread: first press arms (the composer shows what's about to
  # die), second press executes. Esc cancels. The operator's delete verb — Channel refuses root.
  defp handle_key(%{key: :char, char: "d", ctrl: true}, state), do: {:noreply, schedule_render(delete_selected(state))}

  defp handle_key(%{key: :escape}, %{pending_delete: {:armed, _}} = state),
    do: {:noreply, schedule_render(%{state | pending_delete: nil})}

  defp handle_key(%{key: :char, char: "u", ctrl: true}, state), do: host(state, :clear)
  defp handle_key(%{key: :char, char: "n", ctrl: true}, state), do: host(state, :new_task)
  defp handle_key(%{key: :char, ctrl: true}, state), do: {:noreply, state}
  defp handle_key(%{key: :char, char: c}, state), do: host(state, {:putc, c})
  defp handle_key(%{key: :space}, state), do: host(state, {:putc, " "})
  defp handle_key(%{key: :backspace}, state), do: host(state, :backspace)
  defp handle_key(%{key: :escape}, state), do: host(state, :cancel)
  defp handle_key(%{key: :enter}, state), do: {:noreply, schedule_render(submit(state))}
  defp handle_key(%{key: :up}, state), do: {:noreply, select(state, -1)}
  defp handle_key(%{key: :down}, state), do: {:noreply, select(state, 1)}
  defp handle_key(%{key: :page_up}, state), do: {:noreply, scroll_by(state, -page(state))}
  defp handle_key(%{key: :page_down}, state), do: {:noreply, scroll_by(state, page(state))}
  defp handle_key(%{key: :home}, state), do: {:noreply, schedule_render(%{state | scroll: 0, follow?: false})}
  defp handle_key(%{key: :end}, state), do: {:noreply, schedule_render(%{state | follow?: true})}
  defp handle_key(_key, state), do: {:noreply, state}

  defp host(state, intent), do: {:noreply, schedule_render(%{state | view: Host.handle_key(state.view, intent)})}

  # Landing on a thread re-pins the conversation to its tail (you're opening it, Slack-style).
  defp select(state, delta),
    do: schedule_render(%{state | view: Host.select(state.view, delta, state.root_id), follow?: true, scroll: 0})

  # Submit the composer: a reply into the open thread, or (Ctrl+N intent / no thread yet) a new
  # task thread. Failures just keep the draft rather than crash the tab.
  defp submit(state) do
    text = String.trim(state.view.input)

    cond do
      text == "" -> state
      state.view.intent == :new or is_nil(state.view.selected_id) -> submit_new(state, text)
      true -> submit_reply(state, state.view.selected_id, text)
    end
  rescue
    _ -> state
  catch
    :exit, _ -> state
  end

  # Reply straight into the open thread and self-wake its lead/@-mentions. Unlike a new thread
  # there's no cockpit staffing to defer to: the cockpit only wakes for messages on its own bus,
  # which it never sees from our cross-process DB post — so we always wake here.
  defp submit_reply(state, thread_id, text) do
    author = operator()
    Channel.post(%{thread_id: thread_id, author: author, body: text})
    wake_mentions(author, text, thread_id)
    %{state | view: Host.after_submit(state.view), follow?: true}
  end

  # Kick off a new thread/task: open a machine-scope funes thread titled by the text, post it as
  # the operator, staff a lead, then OPEN the new thread in the center.
  defp submit_new(state, text) do
    author = operator()

    case Channel.open_thread(%{title: text, scope: "machine"}) do
      {:ok, thread} ->
        Channel.post(%{thread_id: thread.id, author: author, body: text})

        case stage_lead(thread.id, text) do
          # The cockpit (a SEPARATE beam) spawns a dedicated leaf session for any WORKER lead and
          # injects the opening turn ITSELF (`ensure_thread_sessions`). Waking the standing
          # coworker from here too is the "both claudes answered" duplicate — so only wake from
          # here for a lead the cockpit won't staff (a meta/unknown lead).
          {:ok, lead} -> if !cockpit_staffs?(lead), do: wake_mentions(author, text, thread.id)
          {:error, reason} -> note_no_lead(thread.id, reason)
        end

        view = %{Host.after_submit(state.view) | selected_id: thread.id}
        %{state | view: view, follow?: true, scroll: 0}

      _ ->
        state
    end
  end

  defp operator, do: Application.get_env(:server, :operator, "andrew")

  # Staff the picked coworker as the new thread's lead: the composer text's first @-mention, else
  # intent triage, else the operator's persisted override / the LIVE workspace roster's worker
  # default. Returns `{:ok, handle}` on a real staffing, `{:error, reason}` when nobody resolves
  # or `assign_lead` can't bind the handle — the caller surfaces it instead of opening a
  # leaderless, silent thread. The thread + opening message are already durable regardless.
  defp stage_lead(thread_id, text) do
    roster = active_roster()
    default = Config.default_coworker_override() || Staffing.default_coworker(roster)

    case Staffing.pick_coworker(text, default, roster) do
      nil ->
        {:error, :no_coworker}

      handle ->
        with {:ok, ^handle} <- stage(thread_id, handle) do
          note_staffing(thread_id, handle, Staffing.route_reason(text, handle, roster))
          {:ok, handle}
        end
    end
  end

  # `Server.assign_lead/2` returns `{:error, :no_agent}` for a handle that was never registered — a
  # no-op, not a raise — so we check it rather than assume success.
  defp stage(thread_id, handle) do
    case Server.assign_lead(thread_id, handle) do
      {:error, reason} -> {:error, reason}
      _ -> {:ok, handle}
    end
  end

  # The Slack-style system line: who leads this thread and WHY (mention / triage / default).
  # The why makes triage misroutes visible in the transcript itself — the observability half.
  # Best-effort; a post failure never blocks the staffing.
  defp note_staffing(thread_id, handle, reason) do
    why =
      case reason do
        :mention -> "you named them"
        :triage -> "triaged from the task text"
        :default -> "default lead"
      end

    Channel.post(%{thread_id: thread_id, author: "aleph", body: "→ #{handle} leads (#{why})"})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # Surface a leaderless thread in the feed itself (the operator sees WHY it's quiet) rather than
  # silently eating the message. Best-effort: a post failure just leaves the thread quiet.
  defp note_no_lead(thread_id, reason) do
    Channel.post(%{
      thread_id: thread_id,
      author: "aleph",
      body: "⚠ no coworker staffed (#{inspect(reason)}) — nobody is listening on this thread yet." <> no_lead_hint(reason)
    })

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # `:no_coworker` = the worker-only default resolved nobody (Slice B: the meta surveyor never
  # leads) — tell the operator the fix, not just the symptom.
  defp no_lead_hint(:no_coworker), do: " Add a worker (builder/planner/reviewer/…) to the workspace's roster."
  defp no_lead_hint(_reason), do: ""

  # Does the cockpit spawn a per-thread leaf session for this lead (so it owns the opening turn
  # and we must NOT also wake here)? Mirrors `Console.Cockpit.leaf_staffed?/2`: any WORKER roster
  # lead — claude or pi harness — gets its own leaf window; only a meta (surveyor) or
  # roster-unknown lead is still woken from here.
  defp cockpit_staffs?(lead), do: lead in Profiles.leaf_handles(active_roster())

  # The active Workspace's roster, read STRAIGHT from funes (not via `Space`/`Console.Workspaces`): this is
  # the machine-chat reader beam — it never starts aleph's supervision tree, so the `Console.Workspaces`
  # cache GenServer isn't here. Server-down / no workspace → `[]` (nobody wakes).
  defp active_roster do
    case live_workspace() do
      %{roster: [_ | _] = roster} -> roster
      _ -> []
    end
  end

  # The first live funes workspace (Slice 1: the single machine Workspace). A plain `Repo.all` under the
  # hood — works in any beam funes booted in, unlike the cockpit-only `Console.Workspaces` cache.
  defp live_workspace do
    case Server.Workspaces.all() do
      [workspace | _] -> workspace
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # Which per-thread window a reply's wake must land on — mirrors `Console.Cockpit.delivery_target/3`.
  # A worker-led STAFFED leaf runs the episode in its own window, so its reply must reach THAT
  # session, not the lead's standing handle→window slot. The standing thread has no leaf window,
  # so the probe returns nil and routing falls back to the standing window.
  defp staffed_window(lead, thread_id) do
    if cockpit_staffs?(lead), do: live_leaf_window(thread_id)
  end

  # The leaf's live window NAME for `thread_id`: the `@funes_thread`-stamped window (the routing
  # map, read from tmux itself), else the legacy `t<id>` name. nil when the leaf has no window.
  defp live_leaf_window(thread_id) do
    Enum.find_value(poll_windows(), fn
      %{thread_id: tid, name: name} when tid == thread_id -> name
      %{name: name} -> if name == "t#{thread_id}", do: name
    end)
  end

  # Wake each @-mentioned coworker by injecting the message as a turn into its tmux window — the
  # same send-keys the cockpit does, but from here (our post is on our own bus, which the cockpit
  # can't see). $TMUX points at the workspace's server, and `-t <window>` (no session prefix)
  # resolves against the current session.
  defp wake_mentions(author, body, thread_id) do
    lead = safe_thread_lead(thread_id)
    opts = [lead: lead, staffed_window: staffed_window(lead, thread_id)]

    for {window, text} <- Mention.route(%{author: author, body: body, thread_id: thread_id}, opts, active_roster()) do
      System.cmd("tmux", ["send-keys", "-t", window, "-l", text], stderr_to_stdout: true)
      System.cmd("tmux", ["send-keys", "-t", window, "Enter"], stderr_to_stdout: true)
    end

    :ok
  rescue
    _ -> :ok
  end

  # Guarded so a Server hiccup degrades to "wake nobody", never a crash.
  defp safe_thread_lead(tid) do
    Server.thread_lead(tid)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # ── polling edges ────────────────────────────────────────────────────────────────────────────

  # Newest-activity first (the rail order); a transient read failure keeps the last good frame.
  defp poll_blocks(state) do
    Channel.machine_threads()
  rescue
    _ -> state.view.blocks
  catch
    :exit, _ -> state.view.blocks
  end

  # The live windows + their leaf tags + last-activity stamps — the presence/typing signal.
  # `general` (this tab) is excluded: its activity is our own painting.
  defp poll_windows do
    case System.cmd(
           "tmux",
           ["list-windows", "-F", "\#{window_name}\t\#{@funes_thread}\t\#{window_activity}"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> out |> Presence.parse_windows() |> Enum.reject(&(&1.name == "general"))
      _ -> []
    end
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  # thread_id → lead handle for every polled thread (per-thread Repo reads; the poll is 700ms and
  # the thread count small). A funes hiccup degrades to the last known leads.
  # ── painting ─────────────────────────────────────────────────────────────────────────────────
  defp poll_leads(blocks, state) do
    Map.new(blocks, fn %{thread: %{id: id}} -> {id, safe_thread_lead(id)} end)
  rescue
    _ -> state.leads
  catch
    :exit, _ -> state.leads
  end

  # The ROOT thread — tertius's home, the rollup surface the rail pins first: the thread whose
  # lead is a META (surveyor) roster handle. nil when none reads as one (Host falls back to the
  # newest thread).
  defp root_id(blocks, leads, roster) do
    metas =
      for entry <- roster,
          %{archetype: arch, name: name} = Profiles.roster_entry(entry),
          arch != nil and Profiles.meta?(arch),
          do: "#{name}-machine"

    Enum.find_value(blocks, fn %{thread: %{id: id}} -> if leads[id] in metas and metas != [], do: id end)
  end

  defp safe_rollup(state) do
    Console.Orbis.rollup()
  rescue
    _ -> state.rollup
  catch
    :exit, _ -> state.rollup
  end

  # ── center scroll ────────────────────────────────────────────────────────────────────────────

  # Follow is armed/disarmed ONLY by explicit user intent: scrolling up unpins; scrolling DOWN
  # onto the bottom re-pins (plus End and a submit). paint/1 never re-arms it from position alone.
  defp scroll_by(state, delta) do
    scroll = (state.scroll + delta) |> min(state.max_scroll) |> max(0)

    follow? =
      cond do
        delta < 0 -> false
        delta > 0 and scroll >= state.max_scroll -> true
        true -> state.follow?
      end

    schedule_render(%{state | scroll: scroll, follow?: follow?})
  end

  defp page(state), do: max(Layout.compute(state.w, state.h).center.h - 1, 1)

  # The :poll body, callable inline (post-delete) without re-arming the poll timer.
  defp poll_refresh(state) do
    blocks = poll_blocks(state)
    windows = poll_windows()
    leads = poll_leads(blocks, state)
    roster = active_roster()
    root_id = root_id(blocks, leads, roster)

    %{
      refresh_size(state)
      | view: Host.merge(state.view, blocks, root_id),
        windows: windows,
        leads: leads,
        roster: roster,
        root_id: root_id,
        rollup: safe_rollup(state),
        now_s: System.os_time(:second)
    }
  end

  # Second Ctrl+D on the ARMED thread: hard-delete and refresh the view in place.
  defp delete_selected(%{pending_delete: {:armed, id}} = state) do
    state = %{state | pending_delete: nil}

    with %{thread: %{id: ^id} = thread} <- Host.selected_block(state.view),
         {:ok, _} <- Channel.delete_thread(thread) do
      poll_refresh(state)
    else
      {:error, reason} -> %{state | pending_delete: {:refused, inspect(reason)}}
      _ -> state
    end
  end

  # First Ctrl+D: arm on the rail-selected thread (no selection → no-op).
  defp delete_selected(state) do
    case Host.selected_block(state.view) do
      nil -> state
      block -> %{state | pending_delete: {:armed, block.thread.id}}
    end
  end

  defp refresh_size(state) do
    :termbox2_nif.tb_resize()
    %{state | w: max(:termbox2_nif.tb_width(), 1), h: max(:termbox2_nif.tb_height(), 1)}
  end

  defp schedule_render(%{render_armed?: true} = state), do: state

  defp schedule_render(state) do
    Process.send_after(self(), :render, @render_coalesce_ms)
    %{state | render_armed?: true}
  end

  defp paint(state) do
    cw = Layout.compute(state.w, state.h).composer.w - 2
    l = Layout.compute(state.w, state.h, length(compose_lines(state.view.input, cw)))

    rows = conversation_rows(state, l.center.w - 2)
    max_scroll = max(length(rows) - l.center.h, 0)
    scroll = if state.follow?, do: max_scroll, else: min(state.scroll, max_scroll)
    windowed = rows |> Enum.drop(scroll) |> Enum.take(l.center.h)
    top_pad = List.duplicate([], max(l.center.h - length(windowed), 0))

    cells =
      Board.rows_to_cells([header_row(state)], l.header) ++
        pane_cells(l.rail, rail_rows(state, l.rail)) ++
        sep_cells(l.rail_sep) ++
        Board.rows_to_cells(top_pad ++ windowed, inset(l.center)) ++
        pane_cells(l.crew, crew_rows(state, l.crew)) ++
        sep_cells(l.crew_sep) ++
        Board.rows_to_cells(composer_rows(state, cw, l.composer.h), inset(l.composer))

    Board.paint(cells)
    %{state | scroll: scroll, max_scroll: max_scroll}
  end

  defp pane_cells(nil, _rows), do: []
  defp pane_cells(rect, rows), do: Board.rows_to_cells(rows, rect)

  defp sep_cells(nil), do: []
  defp sep_cells(rect), do: Board.rows_to_cells(List.duplicate([{"│", :separator}], rect.h), rect)

  # A one-column breathing inset for the text panes (center + composer).
  defp inset(rect), do: %{rect | x: rect.x + 1, w: max(rect.w - 2, 1)}

  # `TLÖN · 3 threads · 1 working  ORBIS 2 open · 1 stalled · 4 done`
  defp header_row(state) do
    open = Enum.count(state.view.blocks, &(&1.thread.state != "closed"))
    working = Presence.working_count(state.windows, state.now_s)
    gated = Enum.count(state.view.blocks, &Map.get(&1.thread, :awaiting))
    gate_seg = if gated > 0, do: [{" · #{gated} gated", :warm}], else: []

    orbis =
      case state.rollup do
        %{summary: summary} -> [{"  ORBIS ", :accent} | Console.Panel.Leaves.summary_row(summary)]
        _ -> []
      end

    [{" TLÖN ", :header}, {"· #{open} threads · #{working} working", :dim}] ++ gate_seg ++ orbis
  end

  defp rail_rows(_state, nil), do: []

  defp rail_rows(state, rect) do
    rows =
      state.view.blocks
      |> Host.ordered(state.root_id)
      |> Enum.map(fn block ->
        id = block.thread.id

        %{
          id: id,
          title: rail_title(block, id, state.root_id),
          state: block.thread.state,
          status: Presence.thread_status(state.windows, id, state.now_s),
          unread: Host.unread(state.view, block),
          stage: Map.get(block.thread, :stage),
          awaiting: Map.get(block.thread, :awaiting)
        }
      end)

    Rail.render(%{rows: rows, selected_id: state.view.selected_id}, rect)
  end

  defp rail_title(block, id, root_id) do
    title = block.thread.title || "untitled"
    if id == root_id, do: "⌂ " <> title, else: title
  end

  defp crew_rows(_state, nil), do: []

  defp crew_rows(state, rect) do
    led_by =
      state.leads
      |> Enum.reject(fn {_tid, lead} -> is_nil(lead) end)
      |> Enum.group_by(fn {_tid, lead} -> lead end, fn {tid, _lead} -> tid end)

    titles = Map.new(state.view.blocks, fn b -> {b.thread.id, b.thread.title} end)
    coworkers = Crew.coworkers(state.roster, state.windows, led_by, titles, %{}, state.now_s)

    Crew.render(%{coworkers: coworkers, leaves: {Enum.count(state.windows, &leaf?/1), Config.max_leaves()}}, rect)
  end

  defp leaf?(%{thread_id: tid}) when is_integer(tid), do: true
  defp leaf?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)

  # The open conversation: a title bar, the turn-grouped transcript, and a working indicator when
  # the leaf's harness is actively painting (the "typing…" of this surface).
  defp conversation_rows(state, w) do
    case Host.selected_block(state.view) do
      nil ->
        [[{"no machine threads yet — type a task and press Enter", :dim}]]

      block ->
        id = block.thread.id
        lead = state.leads[id]
        closed = if block.thread.state == "closed", do: " · closed", else: ""

        head = [
          [{"▍ ", :accent}, {block.thread.title || "untitled", :header}, {"  #{lead || "unstaffed"}#{closed}", :dim}],
          blank()
        ]

        working =
          if Presence.thread_status(state.windows, id, state.now_s) == :working and lead,
            do: [blank(), [{"⋯ #{lead} is working…", :accent}]],
            else: []

        head ++ Transcript.thread_rows(block, w) ++ working
    end
  end

  # The composer: a blank spacer, a rule, then the FULL buffer wrapped to the width — the box
  # grows with it (Layout caps at half the body; past the cap the window keeps the cursor's
  # tail line). Reply into the open thread by default, a new task after Ctrl+N.
  @doc false
  def composer_rows(state, cw, box_h) do
    input = state.view.input
    {glyph, hint} = composer_prompt(state)

    lines =
      cond do
        confirm = confirm_row(state) -> [confirm]
        input == "" -> [[{glyph, :accent}, {hint, :dim}]]
        true -> input |> compose_lines(cw) |> Enum.take(-(box_h - 2)) |> glyph_rows(glyph)
      end

    [[], [{String.duplicate("─", max(cw, 1)), :separator}] | lines]
  end

  # The delete confirm/refusal line takes the composer over — a draft survives underneath.
  defp confirm_row(%{pending_delete: {:armed, _id}} = state) do
    title =
      case Host.selected_block(state.view) do
        %{thread: %{title: t}} -> t || "untitled"
        _ -> "untitled"
      end

    [{"✕ ", :accent}, {"delete \"#{title}\" and its messages? Ctrl+D confirms · Esc cancels", :dim}]
  end

  defp confirm_row(%{pending_delete: {:refused, why}}), do: [{"✕ ", :accent}, {"delete refused: #{why}", :dim}]
  defp confirm_row(_state), do: nil

  # The wrapped buffer with the `▎` cursor marker at the tail — Panel.Composer's wrap, the
  # cockpit compose box's exact behavior. Layout sizes the box from its length.
  @doc false
  def compose_lines(input, cw) do
    Panel.Composer.lines(%{buffer: input, cursor: String.length(input)}, Panel.Composer.text_width(cw))
  end

  defp glyph_rows([first | rest], glyph) do
    [
      [{glyph, :accent} | Panel.Composer.marker_runs(first)]
      | Enum.map(rest, &[{"  ", :normal} | Panel.Composer.marker_runs(&1)])
    ]
  end

  defp composer_prompt(%{view: %{intent: :new}}), do: {"＋ ", "new task — type and press Enter · Esc back to reply"}

  defp composer_prompt(state) do
    case Host.selected_block(state.view) do
      nil -> {"＋ ", "new task — type and press Enter"}
      block -> {"↳ ", "reply to #{block.thread.title || "untitled"} — Enter sends · Ctrl+N new task"}
    end
  end

  @impl true
  def terminate(_reason, state), do: teardown(state)

  defp teardown(state) do
    try do
      if is_pid(state.driver) and Process.alive?(state.driver), do: GenServer.stop(state.driver, :normal, 500)
    catch
      _, _ -> :ok
    end

    try do
      :termbox2_nif.tb_shutdown()
    catch
      _, _ -> :ok
    end

    restore_host_tty()
  end

  defp restore_host_tty do
    _ = File.write("/dev/tty", @restore)
    :ok
  end
end
