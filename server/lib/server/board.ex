defmodule Server.Board do
  @moduledoc """
  The board's read models (console §4): pure aggregates a TUI (later a LiveView)
  renders, composed from the contexts. §7 — the board holds no truth of its own, it
  reads the public context functions. `brief/1` is the focused thread's brief,
  and is deliberately the SAME one-call read that catches a re-entering session up
  from the dossier rather than the transcript (§3b): one artifact, two consumers.

  Ranked and cut (§6): each pane is capped WITH a count. For an agent briefed from
  this map (the MCP channel's `get_dossier`), a cut without a count reads as "this
  is everything" — the empty-workspace lie in miniature — so TODOS, LEARNINGS,
  UNKNOWNS, BLOCKERS and CHECKS are each `%{shown, more}`.
  """
  import Ecto.Query

  alias Server.Agent
  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Message
  alias Server.Presence.Thinking
  alias Server.Recall
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace

  @cap 5

  @doc """
  The machine-wide activity feed as `{tag, row}` entries, newest-first — the durable backfill for
  the cockpit's in-memory activity ring (a fresh cockpit starts blank; this seeds it so NOW isn't
  empty after a restart). Merges the append-only logs the live feed is dominated by — posted
  messages, banked facts, recorded events — sorted by `created_at`. Transition-only tags
  (issue/question/todo resolved) aren't reconstructable from current state, so they're left to the
  live Bus stream; the seed covers the visible bulk without lying about state.
  """
  @spec recent_activity(pos_integer()) :: [{atom(), map()}]
  def recent_activity(limit \\ 50) do
    entries =
      Enum.map(Channel.recent_across(limit), &{:message_posted, &1}) ++
        Enum.map(recent_facts(limit), &{:fact_banked, &1}) ++
        Enum.map(recent_events(limit), &{:event_recorded, &1})

    entries
    |> Enum.sort_by(fn {_tag, row} -> row.created_at end, {:desc, DateTime})
    |> Enum.take(limit)
  end

  # Recently banked, still-live facts (a forgotten fact is out of every recall surface).
  defp recent_facts(limit) do
    Repo.all(from f in Fact, where: is_nil(f.forgotten_at), order_by: [desc: f.id], limit: ^limit)
  end

  defp recent_events(limit) do
    Repo.all(from e in Event, order_by: [desc: e.id], limit: ^limit)
  end

  @doc """
  The sidebar read-model — the contract the Slack-shaped UI sits on.
  One group per workspace (oldest first): its OPEN threads as ONE unified list — a chat
  thread and a tracked thread are the same kind of row, `stage` nil or set — root first,
  then newest activity; and the workspace's crew with working flags. Each thread row:
  `%{id, title, root, stage, awaiting, lead, working, last_at}`.
  """
  def sidebar do
    thinking = Thinking.thinking_all()
    root_id = with %Thread{id: id} <- Channel.machine_thread(), do: id
    last_by_thread = last_message_at()
    leads = leads_by_thread()
    workspaces = Repo.all(from w in Workspace, order_by: [asc: w.id])
    known = MapSet.new(workspaces, & &1.id)
    default_id = with %Workspace{id: id} <- List.first(workspaces), do: id

    threads =
      from(t in Thread, where: t.state == "open")
      |> Repo.all()
      |> Enum.map(&sidebar_row(&1, root_id, thinking, last_by_thread, leads))

    working_agents =
      thinking |> Map.values() |> List.flatten() |> MapSet.new(& &1.agent)

    for workspace <- workspaces do
      rows =
        threads
        # A thread whose workspace is gone lands in the DEFAULT (oldest) workspace — same
        # never-drop-a-thread stance as Orbis' grouping; the boot repair rehomes it durably.
        |> Enum.filter(fn t ->
          t.workspace_id == workspace.id or (workspace.id == default_id and t.workspace_id not in known)
        end)
        |> Enum.sort_by(&{!&1.root, invert(&1.last_at)})

      %{
        # `icon` is the operator's chosen display icon (`knobs["icon"]`, nil = show the number).
        workspace: %{id: workspace.id, name: workspace.name, icon: (workspace.knobs || %{})["icon"]},
        threads: rows,
        crew: crew_rows(workspace.roster, working_agents)
      }
    end
  end

  defp sidebar_row(thread, root_id, thinking, last_by_thread, leads) do
    %{
      id: thread.id,
      workspace_id: thread.workspace_id,
      title: thread.title,
      root: thread.id == root_id,
      stage: thread.stage,
      awaiting: thread.awaiting,
      lead: Map.get(leads, thread.id),
      working: Map.get(thinking, thread.id, []) != [],
      last_at: Map.get(last_by_thread, thread.id) || thread.created_at
    }
  end

  # DateTime sorts descending via this trick: negate the unix stamp so Enum.sort_by asc works.
  defp invert(nil), do: 0
  defp invert(%DateTime{} = at), do: -DateTime.to_unix(at)

  # Ecto loads the max() aggregate through the field's type, so these are real DateTimes.
  defp last_message_at do
    from(m in Message,
      group_by: m.thread_id,
      select: {m.thread_id, max(m.created_at)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # One join for every lead (mirrors staffed_machine_threads), not a per-thread point query.
  defp leads_by_thread do
    from(t in Thread,
      join: a in Agent,
      on: a.id == t.agent_id,
      select: {t.id, a.name}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A roster name matches a working agent bare or with the harness "-machine" suffix.
  defp crew_rows(roster, working_agents) when is_list(roster) do
    Enum.map(roster, fn entry ->
      name = entry["name"] || entry[:name]

      %{
        name: name,
        archetype: entry["archetype"] || entry[:archetype],
        working: name in working_agents or "#{name}-machine" in working_agents
      }
    end)
  end

  defp crew_rows(_roster, _working), do: []

  @doc """
  The IN SCOPE brief for a thread — read fresh from the DB (the argument is just an
  id handle): GOAL (title), the assigned lead, TODOS with the derived NEXT, DONE (the
  merged todo + `work_landed` view), LEARNINGS, UNKNOWNS, BLOCKERS and CHECKS each
  `%{shown, more}`, and RECENT (the message tail).
  """
  def brief(%Thread{} = thread) do
    thread = Repo.get!(Thread, thread.id)
    todos = Dossier.open_todos_for_thread(thread)

    %{
      thread: thread,
      goal: thread.title,
      lead: lead_name(thread),
      todos: todos,
      # NEXT is derived, never stored (§5/§6): the head of the open todos, or nil.
      next: List.first(todos.shown),
      done: done_view(thread),
      # LEARNINGS is the forgetting engine's token-budgeted working set (relevance × strength,
      # design: `docs/plans/2026-08-19-funes-forgetting-design.md`) — not a recency window; `more`
      # counts what fell out of budget (still on disk, `get_facts` returns the total).
      learnings: Recall.thread_learnings(thread),
      # UNKNOWNS beside FACTS — knowing what you don't know is first-class (§4a).
      unknowns: Dossier.open_questions_for_thread(thread),
      blockers: Dossier.open_issues_for_thread(thread),
      # CHECKS — the recent MEASURED verifications (last check red or green), not a self-report.
      checks: Dossier.recent_checks_for_thread(thread),
      recent: Channel.recent_messages(thread, @cap)
    }
  end

  @doc """
  The machine META-view: every OPEN machine-scope thread (root + leaves) as a COMPACT brief — the
  cross-thread read the Orbis Tertius meta agent synthesizes from (design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`). Each thread is trimmed to the synthesis
  essentials — lead, NEXT step, open BLOCKERS, and the message tail — drawn from the SAME `brief/1`
  aggregate a single thread's dossier reads (one read model, not a second truth). Root-first (oldest
  id). Machine-scope only, by construction: `Channel.open_machine_threads/0` never returns project
  work, so this can't become a cross-scope peephole.
  """
  def machine_overview do
    Enum.map(Channel.open_machine_threads(), fn thread ->
      s = brief(thread)

      %{
        thread_id: thread.id,
        title: thread.title,
        lead: s.lead,
        # TRACKED leaves are in this set — carry the signal that says so,
        # or the meta agent sees the thread but not that it's staged/parked on a gate.
        stage: thread.stage,
        awaiting: thread.awaiting,
        next: s.next && s.next.text,
        blockers: Enum.map(s.blockers.shown, & &1.summary),
        recent: Enum.map(s.recent, &%{author: &1.author, body: &1.body})
      }
    end)
  end

  # DONE is a MERGED view (pi doc §5): completed todos by their `done_at`, plus
  # `work_landed` events for outcomes never planned as a todo — merged by their OWN
  # timestamps, never copied into one another (the amended-§4 pattern). Each entry is
  # tagged with its `source` so a renderer can tell a finished step from a shipped
  # outcome; most-recent first, capped WITH a count like every other pane.
  defp done_view(%Thread{} = thread) do
    todos = Enum.map(Dossier.done_todos_for_thread(thread), &%{source: :todo, at: &1.done_at, row: &1})
    events = Enum.map(Dossier.shipped_for_thread(thread), &%{source: :event, at: &1.created_at, row: &1})

    (todos ++ events)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> rank_and_cut()
  end

  # Cap a ranked list and COUNT the cut — never a silent truncation (§5/§6).
  defp rank_and_cut(rows) do
    shown = Enum.take(rows, @cap)
    %{shown: shown, more: length(rows) - length(shown)}
  end

  defp lead_name(%Thread{agent_id: nil}), do: nil

  defp lead_name(%Thread{agent_id: agent_id}) do
    Repo.one(from a in Agent, where: a.id == ^agent_id, select: a.name)
  end
end
