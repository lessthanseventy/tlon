defmodule Console.Reads do
  @moduledoc """
  The render preamble's data assembly: every server/tmux/git READ a frame needs, and the pure
  shaping between them — thread cards, the activity feed's first-sight gate and workspace scoping,
  the focus layout, pane details, the probe cache. `frame/3` is the read-model `Console.View`
  composes; the cockpit calls it once per paint. Nothing here spawns — the find-or-spawn steps
  (`Console.Staffing`) run before it in the preamble. Every read degrades through `Console.Safe`.
  """

  alias Console.Cockpit.Drawer
  alias Console.Panel
  alias Console.Safe
  alias Console.Server.Board
  alias Console.Server.Channel
  alias Console.Server.Projects
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
  defp typing_agent(thinking), do: thinking |> Map.keys() |> List.first()

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

  # What `d` would delete under the current focus: a MEMORY pinned fact (forget), a rail thread, or
  # a rail topic channel (its threads go home to #general). The label rides along for the arm flash.
  def tlon_delete_target(state) do
    case {selected_pinned_fact(state), rail_selection(state)} do
      {%{} = fact, _} -> {:fact, fact, "forget fact ##{fact.id}"}
      {nil, {:thread, %{id: id, title: title}}} -> {:thread, id, "delete “#{title}”"}
      {nil, {:channel, %{kind: "topic"} = channel}} -> {:channel, channel, "delete ##{channel.name}"}
      _ -> nil
    end
  end

  @doc "The rail entry under the nav cursor while the rail is the focused pane, else nil."
  @spec rail_selection(map()) :: {:workspace | :channel | :project | :thread, map()} | nil
  def rail_selection(%{active_key: key, focus: %{in_terminal?: false} = focus} = state) when Space.workspace?(key) do
    layout = tlon_layout(state)

    if Focus.focused_pane(focus, layout) == Panel.Rail,
      do: state |> rail_data() |> Panel.Rail.entries() |> Enum.at(Focus.cursor(focus, layout))
  end

  def rail_selection(_state), do: nil

  @doc "The active workspace's channels, off the last painted sidebar (`[]` before the first frame)."
  @spec channels(map()) :: [map()]
  def channels(state) do
    case Enum.find(state[:sidebar] || [], &(&1.workspace.id == state.active_key)) do
      %{channels: channels} -> channels
      _ -> []
    end
  end

  @doc "The open channel (`state.open_channel` if it still exists, else #general), or nil before the first frame."
  @spec open_channel(map()) :: map() | nil
  def open_channel(state) do
    channels = channels(state)
    id = Panel.Rail.open_channel_id(channels, state[:open_channel])
    Enum.find(channels, &(&1.id == id))
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
    bench = Space.bench(Space.active_workspace_id(state))

    %{
      coworkers: Panel.Crew.coworkers(bench, tabs, led_by, titles, state.thinking, System.os_time(:second)),
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

  # The thread whose lead PTY the right pane can attach to: the OPEN conversation (design 2026-09-08
  # §2 — the terminal sits beside the conversation it belongs to) in a workspace chat view. `false`
  # (the pane forced off) stops the attach too, so a hidden pane costs nothing.
  def session_thread(%{session_pane: false}), do: nil

  def session_thread(%{active_key: key, center_view: :chat, opened_thread: id})
      when Space.workspace?(key) and is_integer(id), do: id

  def session_thread(_state), do: nil

  # The pane's TARGET (nil = no pane): `:auto` follows the coworker — the pane appears once the
  # thread's lead PTY is live and folds away when it isn't; `true`/`false` force it on/off.
  # `live?` is injectable so the read is pure under test (the default asks the live registry).
  def session_pane_target(state, live? \\ &live_session?/1) do
    case session_thread(state) do
      nil -> nil
      id -> if state.session_pane == true or live?.(id), do: id
    end
  end

  # Live = the console holds a running PTY for the thread. The attach itself is unconditional (the
  # cockpit's ensure_session, off `session_thread/1`), so `:auto` can never deadlock waiting on a
  # pane it is itself gating.
  defp live_session?(id), do: is_pid(terminal({:session, id}))

  @doc """
  Alt+\\ walks the pane's mode: `:auto` (follow the coworker) → off → on → `:auto`.

      iex> Console.Reads.cycle_session_pane(:auto)
      false

      iex> Console.Reads.cycle_session_pane(false)
      true

      iex> Console.Reads.cycle_session_pane(true)
      :auto
  """
  def cycle_session_pane(:auto), do: false
  def cycle_session_pane(false), do: true
  def cycle_session_pane(true), do: :auto

  @doc """
  The git pane under the session pane: `{thread_id, worktree}` for the open thread when its worktree
  exists on disk (viewing a thread never creates one), else nil. Off with the session pane.
  `worktree` is injectable so the read stays pure under test.
  """
  def git_pane(state, worktree \\ &existing_worktree/1) do
    with id when is_integer(id) <- session_thread(state),
         path when is_binary(path) <- worktree.(id) do
      {id, path}
    else
      _ -> nil
    end
  end

  defp existing_worktree(id) do
    with true <- Console.Lazygit.available?(),
         {:ok, path} <- Console.Server.cwd_for_thread(id),
         true <- File.dir?(path) do
      path
    else
      _ -> nil
    end
  end

  # The session pane's embedded terminal render-state — the selected thread's live lead PTY, keyed
  # `{:session, id}` in Console.Sessions, or `:no_session` until spawned. LIVE seam: `ensure_session`
  # spawns/attaches the PTY (render + key routing are Andrew's kitty pass).
  defp session_read(state) do
    case session_pane_target(state) do
      id when is_integer(id) -> render_state_of(terminal({:session, id}))
      _ -> :no_session
    end
  end

  # The session pane's PTY is sized to the pane's OWN rect (Console.View.right_rects — the top half of
  # the right column when the git pane shares it), so the attached client draws neither past the
  # frame nor short of it.
  def session_pane_dims(%{w: w, h: h} = state) do
    rect = View.right_rects(w, h, Map.get(state, :input), git_pane(state) != nil).session
    {max(rect.w, 1), max(rect.h, 1)}
  end

  @doc "The git pane's PTY size — the lower half of the right column, from the same split `compose/3` makes."
  def git_pane_dims(%{w: w, h: h} = state) do
    rect = View.right_rects(w, h, Map.get(state, :input), true).git
    {max(rect.w, 1), max(rect.h, 1)}
  end

  def render_state_of(nil), do: :no_session
  def render_state_of(term), do: Terminal.render_state(term)

  # The terminal that owns the keys, by space: a Workspace → the embedded tmux client (still the single
  # `:machine` registry entry in Slice 1 — C2 keys the terminal per workspace id). nil elsewhere (Orbis
  # has no center Terminal — a stale key, or the server-down sentinel).
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
  # The focus walks what the frame PAINTS — UX slice 1 leaves one box on the left, the rail, so the
  # left column is `[Panel.Rail]`. The funes panes (NOW·CREW·MEMORY·STACK) come back into the walk
  # with the drawer that hosts them.
  # While the DRAWER is open its nine panes ARE the walk (UX slice 1, task 4) — the rail isn't
  # walkable then, the drawer covers the centre and owns the keys.
  def tlon_layout(%{drawer: key} = state) when not is_nil(key) do
    %{
      left: Drawer.pane_modules(),
      right: [],
      sections: %{Panel.Memory => memory_sections(state)},
      counts: pane_counts(state)
    }
  end

  def tlon_layout(%{active_key: key} = state) when Space.workspace?(key) do
    case Space.fetch(key) do
      # A stale/removed active_key mid-render (Space.fetch/1 returns nil on a miss) — degrade to
      # the same empty layout a non-Workspace space gets, rather than crash the render.
      nil ->
        %{left: [], right: [], sections: %{}, counts: %{}}

      _space ->
        %{
          left: [Panel.Rail],
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

  # `sidebar`/`stack`/`memory` are cockpit-state keys the drawer's layout also reads; a state that
  # hasn't cached one yet counts zero rows rather than crashing the keypress.

  # The navigable item count per pane, for j/k clamping. Commits = the commit-log length; Memory is
  # sectioned — j/k walks the ACTIVE section's list (pinned=0, habits=1), so its count follows
  # focus.section. Panes without a list are absent (0 → j/k is a no-op there).
  defp pane_counts(state) do
    %{
      Panel.Rail => length(Panel.Rail.entries(rail_data(state))),
      Panel.Stack => length((state[:stack] || @empty_stack).commits),
      Panel.Memory => memory_section_count(state)
    }
  end

  # The rail renders from `reads.sidebar`; `do_render/1` stashes that same read on state so the
  # keyboard (j/k's count, Enter's row) resolves against what is painted, with no second
  # `Board.sidebar/0` round-trip per keypress.
  defp rail_data(state),
    do: %{groups: state[:sidebar] || [], active_key: state.active_key, open_channel: state[:open_channel]}

  @doc """
  What Enter means on the focused pane — the pure half of the cockpit's `:tlon_enter`. The rail
  answers `{:pick, verb}` with one of the verbs `apply_pick/2` already dispatches; STACK zooms
  lazygit; a pane with a detail arms the detail mode; nothing focused (or nothing under the
  cursor) is `:none`, so Enter can never arm a detail that has nothing to show.
  """
  @spec enter_verb(map(), map()) :: {:pick, tuple()} | :lazygit | :ticket_promote | :detail | :none
  def enter_verb(state, layout) do
    case Focus.focused_pane(state.focus, layout) do
      Panel.Rail -> rail_verb(state, layout)
      Panel.Stack -> :lazygit
      Panel.TicketBoard -> :ticket_promote
      # A pane with a detail arms the detail mode — but only when one actually resolved, so Enter
      # can never arm a mode with nothing to show (the next Esc would silently spend it).
      Panel.Memory -> if(tlon_detail(state, layout), do: :detail, else: :none)
      _pane -> :none
    end
  end

  defp rail_verb(state, layout) do
    state
    |> rail_data()
    |> Panel.Rail.entries()
    |> Enum.at(Focus.cursor(state.focus, layout))
    |> case do
      {:thread, %{id: id}} -> {:pick, {:open_thread_view, id}}
      {:channel, %{id: id}} -> {:pick, {:open_channel, id}}
      {:workspace, %{id: id}} -> {:pick, {:switch_space, id}}
      _ -> :none
    end
  end

  defp memory_section_count(%{focus: %{section: 1}, memory: m}) when not is_nil(m), do: length(m.habits)
  defp memory_section_count(%{memory: m}) when not is_nil(m), do: length(m.pinned)
  defp memory_section_count(_state), do: 0

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
      %{state | stack: nil, health: nil, memory: nil, gates: nil}
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

  defp cwd_read(id) when is_integer(id) do
    case Console.Server.cwd_for_thread(id) do
      {:ok, path} -> path
      _ -> nil
    end
  end

  defp cwd_read(_none), do: nil

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
  def center_dims(%{active_key: active_key, w: w, h: h} = state) do
    rect = View.center_rect(active_key, w, h, Map.get(state, :input))
    {max(rect.w, 1), max(rect.h, 1)}
  end

  @doc """
  The active workspace's projects (`%{id, name}`, oldest first) and the one a new thread defaults to —
  the last used (`Server.Projects.last_used/1`), else the first. nil with no workspace or no projects.
  The keymap's Tab cycles over it; the new-thread band names its pick.
  """
  def project_choice(state) do
    with ws when is_integer(ws) <- Space.active_workspace_id(state),
         [_ | _] = projects <- Safe.read(:projects, [], fn -> Projects.in_workspace(ws) end) do
      rows = Enum.map(projects, &%{id: &1.id, name: &1.name})
      last = Safe.read(:last_project, nil, fn -> Projects.last_used(ws) end)
      %{projects: rows, default: if(Enum.any?(rows, &(&1.id == last)), do: last, else: hd(rows).id)}
    else
      _ -> nil
    end
  end

  defp new_thread_project(state) do
    with %{projects: projects, default: default} <- project_choice(state) do
      id = get_in(state, [:input, :project_id]) || default
      Enum.find_value(projects, &(&1.id == id && &1.name))
    end
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

    git = Safe.read(:git_pane, nil, fn -> git_pane(state) end)

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
      # The rail's read-model: workspace groups with their unified thread list (+ crew working
      # flags), each thread carrying the warmth of its live session.
      sidebar: Safe.read(:sidebar, [], fn -> sidebar_read(roster) end),
      open_channel: state[:open_channel],
      # The project the new-thread band will open on — the one Tab picked, else the default.
      new_thread_project: new_thread_project(state),
      # The open thread's worktree path (display only; the spawn ensures it) for the top bar.
      cwd: Safe.read(:cwd, nil, fn -> cwd_read(state.opened_thread) end),
      # CONFIG (the Author, in the drawer): its own cursor.
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
      # The open drawer pane (UX slice 1) — the View reads it for the footer's hints.
      drawer: state[:drawer],
      # TRIAGE is a drawer pane now as well as Orbis' rollup — read it when one of the two shows it
      # (it briefs every thread, so it stays off the per-frame path the rest of the time).
      triage:
        Safe.read(:triage, nil, fn ->
          drawer_triage_read(state, threads)
        end),
      scrolls: state.scrolls,
      input: state.input,
      flash: state.flash,
      receipts: state.receipts,
      # LOCK mode (design 2026-08-23) — the footer's loudest chip.
      lock?: state.lock?,
      # The top bar's server-link alarm. An ambient read, so it belongs here and not in the pure
      # View.compose/3.
      link: Safe.read(:link, :up, fn -> link_state() end),
      # The Workspace space's focus, so the View can light the focused sidebar pane and the status bar
      # can show NAV/TERM. nil elsewhere — no other space navigates panes this way.
      focus: if(Space.workspace?(state.active_key), do: state.focus),
      # The layout the View reads for the focused pane + item cursor (counts), and the resolved
      # MAIN detail (nil unless the focus opened one). Both nil outside a Workspace space.
      tlon_layout: tlon_layout,
      # The right SESSION PANE: the OPEN thread's id when the pane resolves on (else nil → no PTY
      # pane), and its embedded lead PTY render-state. View.compose splits the centre in two when
      # the target is set — or, with a thread open and no session, for the stand-in.
      session_pane: session_pane_target(state),
      # The mode behind that target (:auto | true | false) — the footer names the one Alt+\ is on.
      session_pane_mode: state.session_pane,
      session: Safe.read(:session, :no_session, fn -> session_read(state) end),
      # The git pane under it: the open thread's id when its worktree exists, and lazygit's
      # render-state. View.compose splits the right column when it is set.
      git_pane: git && elem(git, 0),
      git: if(git, do: render_state_of(terminal({:lazygit, elem(git, 0)})), else: :no_session),
      detail:
        Safe.read(:detail, nil, fn ->
          detail_read(state, tlon_layout)
        end)
    }
  end

  defp drawer_triage_read(state, threads) do
    if state[:drawer] == :triage, do: triage_read(threads)
  end

  defp detail_read(state, tlon_layout) do
    if Space.workspace?(state.active_key) and state.focus.detail?, do: tlon_detail(state, tlon_layout)
  end

  # `Server.Board.sidebar/0`'s groups, each thread given the `warm?` of its live session — read off
  # the SAME roster the top bar's lead comes from, so bar and rail can never disagree about warmth.
  # (`awaiting`/`working` ride along from the board; `unread?` waits on message read-state, design
  # 2026-09-08 §4 — a thread without it simply carries no unread badge.)
  defp sidebar_read(roster) do
    warm = for session <- roster, session.warm?, into: MapSet.new(), do: session.thread_id

    warmed = fn threads -> Enum.map(threads, &Map.put(&1, :warm?, MapSet.member?(warm, &1.id))) end

    for group <- Board.sidebar() do
      group
      |> Map.update(:threads, [], warmed)
      |> Map.update(:channels, [], fn channels -> Enum.map(channels, &Map.update(&1, :threads, [], warmed)) end)
    end
  end

  # Only the remote backend can lose its server; an embedded one is reachable by definition.
  defp link_state do
    if Console.Backend.impl() == Console.Backend.Remote and not Console.Backend.Link.up?(),
      do: :down,
      else: :up
  end

  # Sessions is supervised (Console.Supervisor) but the cockpit is NOT — `Sessions.terminal/1`
  # against a torn-down registry exits, which would kill the cockpit and wedge all input. nil reads
  # as "no session"; the supervisor restarts the registry on its own.
  @doc "The live `Console.Terminal` under `key`, or nil (none spawned, or the registry is down)."
  def terminal(key), do: Safe.value(fn -> Sessions.terminal(key) end, nil)
end
