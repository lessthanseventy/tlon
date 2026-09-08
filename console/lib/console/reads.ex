defmodule Console.Reads do
  @moduledoc """
  The render preamble's data assembly: every server/tmux/git READ a frame needs, and the pure
  shaping between them — thread cards, the activity feed's first-sight gate and workspace scoping,
  the focus layout, pane details, the probe cache. `frame/3` is the read-model `Console.View`
  composes; the cockpit calls it once per paint. Nothing here spawns — the find-or-spawn steps
  (`Console.Staffing`) run before it in the preamble. Every read degrades through `Console.Safe`.
  """

  alias Console.Panel
  alias Console.Safe
  alias Console.Server.Board
  alias Console.Server.Channel
  alias Console.Server.Staff
  alias Console.Sessions
  alias Console.Space
  alias Console.Terminal
  alias Console.Tlon.Focus
  alias Console.Tmux
  alias Console.View

  require Space

  @activity_cap 50
  @seen_cap 100

  # Tlön probe cadence: the Stack/Health reads fork subprocesses (git ×~6, nix-env, df, tmux)
  # and open a TCP probe — far too heavy to run per render (a streaming terminal coalesces to
  # ~125 renders/sec, and one nix-env alone exceeds the whole 8ms window; renders serialized
  # and starved input). Probes are CACHED in cockpit state and refreshed at most this often,
  # on the tick; every other render (keys, Bus events, terminal frames) reads the cache.
  @probe_ms 2_000

  # The empty Stack shape non-Tlön spaces (and a not-yet-probed Tlön) render.
  @empty_stack %{branch: nil, dirty: false, ahead: nil, behind: nil, status_summary: nil, commits: [], tools: []}

  # Prepend `{tag, row}` to the activity buffer (newest-first, capped at @activity_cap). Tagged
  # events are already deduped by the `fresh?/3` first-sight gate in handle_info; messages reach
  # the cockpit once (only via the activity topic, since init dropped subscribe_messages).
  def push_activity(state, tag, row) do
    %{state | activity: Enum.take([{tag, row} | state.activity], @activity_cap)}
  end

  # The one-shot backfill behind `activity: []`'s replacement — the durable feed at cockpit start,
  # guarded so a not-yet-up server (init can race the server boot) just yields an empty ring rather
  # than crashing the cockpit. Scoped to the active workspace at render by `scope_activity/2`.
  def seed_activity, do: Safe.read(:activity_seed, [], fn -> Board.recent_activity(@activity_cap) end)

  # First-sight test for a tagged event: true unless its key is already in the recently-seen set.
  # The key is `{tag, row.id}` (a durable row always has an id, so the two topic deliveries share
  # it); a row with no id falls back to the whole `{tag, row}` term.
  def fresh?(state, tag, row), do: seen_key(tag, row) not in state.seen_events

  def seen_key(tag, %{id: id}) when not is_nil(id), do: {tag, id}
  def seen_key(tag, row), do: {tag, row}

  def cap_seen(keys), do: Enum.take(keys, @seen_cap)

  # The stack's own focus: the cockpit's focused thread if it's IN the stack, else the first card —
  # so a card is always active/unfolded even when the cockpit's focus tracks a non-stack thread.
  def stack_focus(blocks, focused_id) do
    ids = Enum.map(blocks, & &1.thread.id)
    if focused_id in ids, do: focused_id, else: List.first(ids)
  end

  # The two-step card set: every thread as a list row; only the `opened` one carries its messages
  # (the conversation view). `active?` is the list cursor; `typing` the thinking chip.
  def thread_cards(blocks, focus, opened, thinking) do
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

  # The pending habit the focus points at, or nil unless: a Workspace space, nav mode, Memory pane,
  # habits section (1), with a habit under the clamped cursor.
  def selected_habit(
        %{active_key: key, memory: %{habits: habits}, focus: %{in_terminal?: false, section: 1} = focus} = state
      )
      when Space.workspace?(key) do
    layout = tlon_layout(state)
    if Focus.focused_pane(focus, layout) == Panel.Memory, do: Enum.at(habits, Focus.cursor(focus, layout))
  end

  def selected_habit(_state), do: nil

  # What `d` would delete under the current focus: a MEMORY pinned fact (forget). The label rides
  # along for the arm flash.
  def tlon_delete_target(state) do
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

  def focused_thread([], _id), do: nil
  def focused_thread(threads, nil), do: List.first(threads)
  def focused_thread(threads, id), do: Enum.find(threads, List.first(threads), &(&1.id == id))

  # The reconcile-on-connect read: whatever the store already holds when the cockpit boots
  # (declares made before this subscribe). Degrades to empty if the store isn't up.
  def thinking_snapshot do
    Safe.value(
      fn ->
        Map.new(Console.Server.Presence.Thinking.thinking_all(), fn {tid, entries} ->
          # Same normalization as the live event path — cockpit state holds unix seconds.
          {tid, Map.new(entries, &{&1.agent, Console.Presence.started_s(&1.started_at)})}
        end)
      end,
      %{}
    )
  end

  # The CREW sidebar's read: the active Workspace's roster joined with the tmux snapshot, the leaf
  # leads, and the thinking declarations (Console.Panel.Crew.coworkers/6). Lead lookups go one
  # server query per live leaf window — at most the leaf cap.
  defp crew_read(state, %{tabs: tabs}) do
    led_by =
      tabs
      |> Enum.filter(&is_integer(&1.thread_id))
      |> Enum.reduce(%{}, fn %{thread_id: tid}, acc ->
        case Console.Server.thread_lead(tid) do
          lead when is_binary(lead) -> Map.update(acc, lead, [tid], &[tid | &1])
          _ -> acc
        end
      end)

    titles = Map.new(state.threads, &{&1.id, &1.title})
    roster = Space.roster(Space.active_workspace_id(state))

    %{
      coworkers: Panel.Crew.coworkers(roster, tabs, led_by, titles, state.thinking, System.os_time(:second)),
      leaves: {Enum.count(tabs, &Tmux.leaf_window?/1), Console.Config.max_leaves()}
    }
  end

  defp crew_read(_state, _machine), do: nil

  # The Tlön center's read: the embedded tmux client. Lookup only — the find-or-spawn lives in
  # ensure_center (render's stateful preamble, via ensure_workspace_roster), so a failing spawn can back
  # off instead of re-materialising the profile and re-issuing tmux new-session every frame.
  defp machine_read(%{active_key: key}) when Space.workspace?(key) do
    case render_state_of(terminal(:machine)) do
      %{} = render_state -> Map.put(render_state, :tabs, Tmux.list_windows(key))
      other -> other
    end
  end

  defp machine_read(_state), do: :no_session

  # The right session pane's TARGET: the stack-focused thread's id when the pane is toggled on in a
  # workspace chat view, else nil (the pane is hidden). Follows the cursor — moving j/k re-targets it,
  # so the pane always shows whatever thread you're looking at.
  def session_pane_target(%{session_pane: true, active_key: key, center_view: :chat, stack_focus: id})
      when Space.workspace?(key) and is_integer(id), do: id

  def session_pane_target(_state), do: nil

  # The session pane's embedded terminal render-state — the selected thread's live lead PTY, keyed
  # `{:session, id}` in Console.Sessions, or `:no_session` until spawned. LIVE seam: `ensure_session`
  # spawns/attaches the PTY (render + key routing are Andrew's kitty pass).
  defp session_read(state) do
    case session_pane_target(state) do
      id when is_integer(id) -> render_state_of(terminal({:session, id}))
      _ -> :no_session
    end
  end

  # The session pane occupies the right column (~⅓ of the center's width) — spawn dims only; the live
  # resize-on-window-change is the kitty pass.
  def session_pane_dims(%{w: w, h: h}), do: {max(div(w, 3) - 2, 1), max(h - 3, 1)}

  def render_state_of(nil), do: :no_session
  def render_state_of(term), do: Terminal.render_state(term)

  # The terminal that owns the keys, by space: a Workspace → the embedded tmux client (still the single
  # `:machine` registry entry in Slice 1 — C2 keys the terminal per workspace id). nil elsewhere (Orbis
  # has no center Terminal — its surface is the Overview).
  def center_terminal(%{active_key: key}) when Space.workspace?(key), do: terminal(:machine)
  def center_terminal(_state), do: nil

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
    do: machine_thread_id(Space.active_workspace_id(state))

  def composer_thread_id(state), do: state.focused_id

  # The shape the Tlön focus SM navigates: the space's two sidebar columns, per-pane section counts
  # (empty until a multi-section pane lands — Memory's coverage/pinned/habits split), and per-pane
  # ITEM counts (what j/k clamps against), derived from the live reads in `state`. Keyed by pane
  # module, matching space.left/right. nil-ish layout for other spaces (the keymap only reads it in
  # Tlön anyway).
  # The Sidebar leads the left column in the FOCUS layout exactly as it does on screen (View
  # prepends it to `space.left`), so `h`/`H` can land on the workspace nav and `Enter` switches.
  def tlon_layout(%{active_key: key} = state) when Space.workspace?(key) do
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

  def tlon_layout(_state), do: %{left: [], right: [], sections: %{}, counts: %{}}

  # HABITS collapses when empty (Panel.Memory), so the Tab ring must shrink with it.
  defp memory_sections(%{memory: %{habits: habits}}) when habits != [], do: 2
  defp memory_sections(_state), do: 1

  def space_at_cursor(state, layout), do: Enum.at(Space.all(), Focus.cursor(state.focus, layout)).key

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

  def fact_detail(nil), do: nil

  def fact_detail(fact) do
    meta =
      [{"kind: #{fact.kind}  ·  #{fact.provenance}", :dim}] ++
        for {label, val} <- [{"check", fact.check_cmd}, {"incident", fact.incident}, {"taught", fact.taught}],
            is_binary(val) and val != "",
            do: {"#{label}: #{val}", :dim}

    %{title: "FLOOR FACT", lines: [{"", :normal}, {fact.text, :normal}, {"", :normal} | meta]}
  end

  def habit_detail(nil), do: nil

  def habit_detail(habit) do
    by = if is_binary(habit.proposed_by), do: "  ·  proposed by #{habit.proposed_by}", else: ""

    rationale =
      if is_binary(habit.rationale) and habit.rationale != "", do: [{"", :normal}, {habit.rationale, :dim}], else: []

    %{title: "PENDING HABIT#{by}", lines: [{"", :normal}, {habit.text, :normal} | rationale]}
  end

  defp commit_detail(state, index) do
    case Enum.at((state.stack || @empty_stack).commits, index) do
      %{hash: hash, subject: subject} ->
        dir = workspace_repo_dir(Space.active_workspace_id(state))
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
  def machine_thread_id(workspace_id) do
    case machine_thread(workspace_id) do
      %{id: id} -> id
      _ -> nil
    end
  end

  # Prefer the workspace's own root; else ANY open machine thread (a pre-bootstrap DB, the test
  # harness's cache-only workspaces) rather than proliferating a fresh one.
  def machine_thread(workspace_id), do: Channel.machine_thread(workspace_id) || Channel.machine_thread()

  # Expire cached probes once @probe_ms has passed; render's ensure_probes refills lazily.
  def maybe_expire_probes(state) do
    if System.monotonic_time(:millisecond) - state.probed_at >= @probe_ms do
      %{state | stack: nil, health: nil, memory: nil, leaves: nil, gates: nil}
    else
      state
    end
  end

  # Fill the probe cache when a Workspace space is active and the cache is cold. Elsewhere the probes
  # stay nil — git/nix/df/tmux forks and server reads are wasted on spaces that never show them.
  def ensure_probes(%{active_key: key, stack: nil} = state) when Space.workspace?(key) do
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
  def ensure_probes(%{active_key: :orbis, leaves: nil} = state) do
    %{state | leaves: Console.Orbis.rollup(), probed_at: System.monotonic_time(:millisecond)}
  end

  def ensure_probes(state), do: state

  # The Memory pane read: coverage stats + the always-loaded pinned set + the pending-habit queue.
  defp memory_read(workspace_id) do
    %{
      coverage: Console.Server.recall_coverage(workspace_id),
      pinned: Console.Server.pinned(workspace_id),
      habits: Console.Server.pending_habits(workspace_id)
    }
  end

  # The NOW pane's ATTENTION read (Slice 4D): worklines parked awaiting the operator — the gates the
  # `approve N` verb clears. Best-effort; a server hiccup leaves the feed rather than crashing a frame.
  # The active workspace's thread ids as a MapSet (or nil on a server hiccup → unfiltered feed).
  defp workspace_thread_id_set(workspace_id),
    do: Safe.value(fn -> MapSet.new(Console.Server.workspace_thread_ids(workspace_id)) end, nil)

  # Filter the global activity buffer to the active workspace: keep an event when its row has no
  # thread (a global event) or its thread is in the workspace. nil id-set = unfiltered (server down).
  def scope_activity(activity, nil), do: activity

  def scope_activity(activity, %MapSet{} = ids) do
    Enum.filter(activity, fn {_tag, row} ->
      case Map.get(row, :thread_id) do
        nil -> true
        tid -> MapSet.member?(ids, tid)
      end
    end)
  end

  defp gates_read(workspace_id) do
    Safe.value(
      fn ->
        workspace_id
        |> Console.Server.workline_statuses()
        |> Enum.filter(&(&1.awaiting not in [nil, ""]))
        |> Enum.map(&Map.take(&1, [:id, :title, :stage, :awaiting]))
      end,
      []
    )
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
    case Console.Server.repo_for_workspace(workspace_id) do
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
    scopes = for thread <- threads, do: {thread, Board.brief(thread)}

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

  # Size the PTY to EXACTLY the center Terminal's content rect (Console.View.center_rect), so pi never
  # draws past the frame (a wider PTY spills; a shorter one leaves a dead band). The tertius band
  # already shrinks that rect (its own section, not the terminal's), so no separate reserve is needed.
  def center_dims(%{active_key: active_key, w: w, h: h}) do
    rect = View.center_rect(active_key, w, h)
    {max(rect.w, 1), max(rect.h, 1)}
  end

  @doc "The frame's read-model for `Console.View.compose/3` — one call per paint, off the preamble's state."
  def frame(state, stack_blocks, focused) do
    threads = state.threads
    machine = Safe.read(:machine, :no_session, fn -> machine_read(state) end)
    roster = Safe.read(:roster, [], fn -> Staff.roster() end)

    # Computed once — the layout read and the detail read below share it (the detail is resolved
    # against the same frame's layout).
    tlon_layout =
      Safe.read(:tlon_layout, nil, fn -> if(Space.workspace?(state.active_key), do: tlon_layout(state)) end)

    %{
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
      sidebar: Safe.read(:sidebar, [], fn -> Board.sidebar() end),
      # Kitty host? → the Sidebar blanks its fallback glyph so the icon PNG covers cleanly (no bleed).
      graphics?: Console.Graphics.kitty?(),
      workspaces:
        Safe.read(:workspaces, [], fn -> if(state.active_key == :orbis, do: orbis_workspaces(state), else: []) end),
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
      crew: Safe.read(:crew, nil, fn -> crew_read(state, machine) end),
      stack: state.stack || @empty_stack,
      health: state.health,
      activity: scope_activity(state.activity, state.ws_thread_ids),
      gates: state.gates || [],
      memory: if(Space.workspace?(state.active_key), do: state.memory),
      # The center's face (reshape slice D).
      center_view: state.center_view,
      triage: Safe.read(:triage, nil, fn -> if(state.active_key == :orbis, do: triage_read(threads)) end),
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
      session: Safe.read(:session, :no_session, fn -> session_read(state) end),
      detail:
        Safe.read(:detail, nil, fn ->
          if(Space.workspace?(state.active_key) and state.focus.detail?, do: tlon_detail(state, tlon_layout))
        end)
    }
  end

  # Sessions is supervised (Console.Supervisor) but the cockpit is NOT — `Sessions.terminal/1`
  # against a torn-down registry exits, which would kill the cockpit and wedge all input. nil reads
  # as "no session"; the supervisor restarts the registry on its own.
  @doc "The live `Console.Terminal` under `key`, or nil (none spawned, or the registry is down)."
  def terminal(key), do: Safe.value(fn -> Sessions.terminal(key) end, nil)
end
