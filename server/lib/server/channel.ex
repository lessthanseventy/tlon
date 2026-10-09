defmodule Server.Channel do
  @moduledoc """
  The coordination spine (spec §5b): threads and the messages on
  them. The channel is also §4's capture path — a message a participant posts is
  already a durable row, so intent becomes permanent as a side effect of talking.

  This context owns the durable **bus** (§10): rows in SQLite that exist and are
  readable with the BEAM node dead. The reactive **switchboard** — PubSub fan-out
  and waking an external session's pane — is a later layer over these rows, never
  what makes them exist.
  """
  import Ecto.Query

  alias Server.Agent
  alias Server.Event
  alias Server.Fact
  alias Server.Issue
  alias Server.Message
  alias Server.Question
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Thread
  alias Server.Todo

  # The closed thread-scope set (CHECK-guarded in the DB — see the thread_scope migration).
  # Every scope filter pins one of these, so a future third scope is a grep for the attribute,
  # not a hunt for string literals.
  @project_scope "project"
  @machine_scope "machine"

  @doc ~s(Open a thread on the board. Returns `{:ok, thread}` or `{:error, changeset}`.
  `scope` defaults to `"project"`; the Tlön machine-coworker path opens with `"machine"`.)
  def open_thread(attrs) do
    attrs = Map.put_new_lazy(attrs, :workspace_id, &Server.Bootstrap.default_workspace_id/0)
    # a thread lives in a channel (UX slice 1b): the named one, else the workspace's #general
    attrs = Map.put_new_lazy(attrs, :channel_id, fn -> default_channel_id(attrs.workspace_id) end)

    # The lead invariant: a thread is born with a lead (its workspace's manager) unless the caller
    # names one. Enforced HERE, the one creation path, so it holds for operator, MCP, and
    # orchestrator opens alike; the manager staffs it or answers it.
    attrs
    |> Map.put_new_lazy(:agent_id, fn -> designated_lead(attrs[:workspace_id]) end)
    |> Thread.open_changeset()
    |> Repo.insert()
    |> Server.Bus.announce(:thread_opened)
  end

  # the workspace's #general, or nil when the thread has no workspace (a test fixture)
  defp default_channel_id(nil), do: nil
  defp default_channel_id(workspace_id), do: Server.Channels.general(workspace_id).id

  @doc """
  The agent_id of a workspace's designated lead: its manager (`Server.Workspaces.manager/1`), so a
  thread nobody staffed is the manager's to staff rather than the first builder's; a bench without
  one falls back to `Server.Workspaces.lead/1`. nil when there is no workspace or its bench is
  empty (the thread then opens leaderless, healed when a coworker is first staffed).
  """
  def designated_lead(nil), do: nil

  def designated_lead(workspace_id) do
    case Server.Workspaces.manager(workspace_id) || Server.Workspaces.lead(workspace_id) do
      %Server.Coworker{agent_id: agent_id} -> agent_id
      nil -> nil
    end
  end

  @doc """
  Post a message to a thread — the capture path. Returns `{:ok, message}` or
  `{:error, changeset}` on a missing thread/author/body. A thread that does not
  exist is refused by SQLite's own foreign key (it raises), never by a mirrored
  check here (§10).
  """
  def post(attrs) do
    with {:ok, message} <- attrs |> Message.post_changeset() |> Repo.insert() do
      # Announce the durable row (liveness only, §10) — a broadcast with no
      # subscriber is a harmless no-op.
      Server.Bus.broadcast({:message_posted, message})
      {:ok, Server.Recall.embed_on_write(message)}
    end
  end

  @doc ~s{Close a thread. Its messages are untouched — history outlives the close. A CHILD thread
  (one with a `parent_thread_id`, Slice 4D) reports up on close: funes posts a system summary into
  the parent thread, `@mentioning` its lead so the switchboard wakes them.}
  def close_thread(%Thread{} = thread) do
    result =
      thread
      |> Thread.state_changeset("closed")
      |> Repo.update()
      |> Server.Bus.announce(:thread_closed)

    with {:ok, _closed} <- result do
      Staff.end_thread_sessions(thread.id)
      Server.Tickets.done_for(thread.id)
      report_to_parent(thread)
    end

    result
  end

  # The report-up wake: a closed child posts `✅ child #N “title” closed` into its parent, prefixed
  # with `@<lead>` when the parent has one (the mention wakes the manager). Best-effort — a report
  # failure never blocks the close. Top-level threads (no parent) report nothing.
  defp report_to_parent(%Thread{parent_thread_id: nil}), do: :ok

  defp report_to_parent(%Thread{parent_thread_id: parent_id} = child) do
    mention = if lead = thread_lead(parent_id), do: "@#{lead} ", else: ""
    post(%{thread_id: parent_id, author: "tlon", body: "#{mention}✅ child ##{child.id} “#{child.title}” closed"})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Hard-delete a thread — the operator's cleanup verb, never an agent tool. Thread-scoped
  rows (messages, todos, questions, sessions) go with it; knowledge and ledger rows
  (facts, issues, events) survive with the thread link cleared. The ROOT machine thread
  is refused: it is the standing coworkers' permanent home (see `machine_thread/0`).
  """
  def delete_thread(%Thread{} = thread) do
    if root_machine_thread?(thread) do
      {:error, :root_machine_thread}
    else
      {:ok, deleted} = Repo.transaction(fn -> purge_thread(thread) end)
      Server.Bus.announce({:ok, deleted}, :thread_deleted)
    end
  end

  # The transactional body: unlink the surviving rows, delete the thread-scoped ones, record the
  # deletion itself (who/when/title — the only trace once the row below is gone), then the row.
  defp purge_thread(thread) do
    for schema <- [Fact, Issue, Event] do
      Repo.update_all(from(r in schema, where: r.thread_id == ^thread.id), set: [thread_id: nil])
    end

    # what points INTO the rows about to go: unlinked, never deleted with them
    sessions = from(r in Session, where: r.thread_id == ^thread.id, select: r.id)
    messages = from(r in Message, where: r.thread_id == ^thread.id, select: r.id)
    Repo.update_all(from(f in Fact, where: f.source_session_id in subquery(sessions)), set: [source_session_id: nil])
    Repo.update_all(from(m in Message, where: m.reply_to in subquery(messages)), set: [reply_to: nil])
    Repo.update_all(from(t in Thread, where: t.parent_thread_id == ^thread.id), set: [parent_thread_id: nil])

    for schema <- [Server.Habit, Server.Playbook] do
      Repo.update_all(from(r in schema, where: r.source_thread_id == ^thread.id), set: [source_thread_id: nil])
    end

    for schema <- [Message, Todo, Question, Session] do
      Repo.delete_all(from(r in schema, where: r.thread_id == ^thread.id))
    end

    {:ok, _} =
      Server.Dossier.record_event(%{
        kind: "thread_deleted",
        correlation: "thread:#{thread.id}",
        detail: %{
          "thread_id" => thread.id,
          "title" => thread.title,
          "deleted_by" => Application.get_env(:server, :operator, "andrew")
        }
      })

    Repo.delete!(thread)
  end

  @doc "Whether `thread` IS the root machine thread — the standing coworkers' permanent home.
  Public: delete_thread refuses it here, and Workline.promote refuses to track it."
  def root_machine_thread?(%Thread{scope: @machine_scope} = thread) do
    # Root-ness is per-workspace (each workspace has its own root): a thread is THE root only if it
    # is the oldest open stage-less machine thread in ITS OWN workspace. A nil workspace_id
    # (pre-bootstrap threads) falls through to the global oldest.
    case machine_thread(thread.workspace_id) do
      %Thread{id: root_id} -> root_id == thread.id
      nil -> false
    end
  end

  def root_machine_thread?(_thread), do: false

  @doc "Open PROJECT threads only, newest first — closed and machine-scope threads are omitted.
  The machine thread (the Tlön coworker) is filtered out of the project surfaces; reach it via
  `machine_thread/0` or by id."
  def open_threads do
    Repo.all(from t in Thread, where: t.state == "open" and t.scope == ^@project_scope, order_by: [desc: t.id])
  end

  @doc """
  Whether `thread` is its workspace's standing thread (the lobby, `machine_thread/1`): every
  coworker's home window lives on it, so it is never an agent's to close.
  """
  def standing?(%Thread{id: id, workspace_id: ws}) when not is_nil(ws), do: match?(%Thread{id: ^id}, machine_thread(ws))

  def standing?(_thread), do: false

  @doc ~s"""
  The ROOT machine thread — the OLDEST open machine-scope thread, or nil. The founding machine
  thread: the standing coworkers' permanent home and the Orbis Tertius meta thread (design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`). Also the find-or-create lookup for
  the Tlön machine coworker, so it reuses a persistent thread across restarts.

  Oldest, NOT newest: a staffed child thread can be machine-scope too (a workline always is), so a
  `[desc: t.id]` "latest machine thread" could return a child, not the root. Child threads are always newer
  than the root, so `[asc: t.id]` returns the root and only the root (until it is closed, which
  rotation/`clear-machine-threads` must not do).
  """
  def machine_thread(workspace_id \\ nil) do
    from(t in Thread,
      where: t.state == "open" and t.scope == ^@machine_scope and is_nil(t.stage),
      order_by: [asc: t.id],
      limit: 1
    )
    |> scope_workspace(workspace_id)
    |> Repo.one()
  end

  # Optionally narrow a machine-thread query to one workspace. `nil` = every workspace (the
  # pre-multiplicity global behaviour, kept for callers with no workspace in hand).
  defp scope_workspace(query, nil), do: query
  defp scope_workspace(query, workspace_id), do: from(t in query, where: t.workspace_id == ^workspace_id)

  @doc """
  Every OPEN machine-scope thread, oldest-first (the root leads) — the child set the Orbis Tertius
  meta agent reads across (`Server.Board.machine_overview/0`). Open-only: the synthesis is over work
  in flight, not the closed history.
  """
  def open_machine_threads do
    # TRACKED child threads (worklines) stay in: filtering on `is_nil(stage)` here would drop
    # exactly the leaves doing real work from the meta agent's overview. Only ROOT resolution
    # (machine_thread/0) excludes staged threads: the root is never a work item.
    Repo.all(
      from t in Thread,
        where: t.state == "open" and t.scope == ^@machine_scope,
        order_by: [asc: t.id]
    )
  end

  @doc """
  STAFFED, OPEN machine-scope threads — the staffing pass's candidate list (`Server.Staffing`):
  every open machine-scope thread with a lead, `%{id, lead, title}` per thread (`lead` is the
  staffed agent's name; the join makes it never nil). Open-only: a child's window is torn down
  when its thread closes, so a closed thread in this list would be killed and respawned every
  pass. No ordering guarantee — the caller dedups against live tmux windows.
  """
  def staffed_machine_threads(workspace_id \\ nil) do
    from(t in Thread,
      join: a in Agent,
      on: a.id == t.agent_id,
      where: t.scope == ^@machine_scope and t.state == "open" and not is_nil(t.agent_id),
      select: %{id: t.id, lead: a.name, title: t.title, workspace_id: t.workspace_id}
    )
    |> scope_workspace(workspace_id)
    |> Repo.all()
  end

  @doc """
  ALL machine-scope threads as THREAD BLOCKS.
  Like `chorus/1` but scoped to `machine` and WITHOUT the open-only filter: a rotated (closed)
  machine thread must still surface as history, so the chat can fold it below the current one.
  Each block carries the thread's recent messages (chat order within), most-recent-activity FIRST.
  `[%{thread, messages}]`.
  """
  def machine_threads(workspace_id \\ nil, per_thread \\ 20) do
    # Worklines stay IN the chat surface — the spec interview happens on the workline thread.
    # Only ROOT resolution (machine_thread/1) and the surveyor's child set exclude them.
    # `workspace_id` scopes the stack to the active workspace (nil = every workspace).
    from(t in Thread, where: t.scope == ^@machine_scope)
    |> scope_workspace(workspace_id)
    |> thread_blocks(per_thread)
  end

  @doc """
  Every CLOSED thread, any workspace, newest activity first (its last message, else its birth) —
  the operator's history (the imported Claude Code conversations among them).
  `%{id, title, workspace_id, project, at}` per row; `project` is the project name or nil. Capped.
  """
  def closed_threads(limit \\ 200) do
    last = from(m in Message, group_by: m.thread_id, select: %{thread_id: m.thread_id, at: max(m.created_at)})

    Repo.all(
      from t in Thread,
        where: t.state == "closed",
        left_join: l in subquery(last),
        on: l.thread_id == t.id,
        left_join: p in Server.Project,
        on: p.id == t.project_id,
        order_by: [desc: coalesce(l.at, t.created_at), desc: t.id],
        limit: ^limit,
        select: %{
          id: t.id,
          title: t.title,
          workspace_id: t.workspace_id,
          project: p.name,
          at: coalesce(l.at, t.created_at)
        }
    )
  end

  @doc """
  Reopen a closed thread. A thread with no lead (an imported conversation) takes its workspace's
  designated lead, so the staffing pass has someone to wake. `{:ok, thread}` | `{:error, cs}`.
  """
  def reopen_thread(%Thread{} = thread) do
    thread
    |> Thread.state_changeset("open")
    |> Ecto.Changeset.put_change(:agent_id, thread.agent_id || designated_lead(thread.workspace_id))
    |> Repo.update()
    |> Server.Bus.announce(:thread_opened)
  end

  @doc """
  Reopen `thread_id` if it is closed — what an operator reply to a history thread does first, so the
  reply wakes a lead instead of landing in a thread nothing staffs. `{:reopened, thread}`, `:open`
  when it already was, `:no_thread`, or `{:error, changeset}`.
  """
  def reopen_if_closed(thread_id) do
    case thread(thread_id) do
      nil ->
        :no_thread

      %Thread{state: "closed"} = closed ->
        with {:ok, reopened} <- reopen_thread(closed), do: {:reopened, reopened}

      %Thread{} ->
        :open
    end
  end

  @doc "A thread by id, or nil — the load path for the cross-thread `close_thread` verb."
  def thread(id), do: Repo.get(Thread, id)

  @doc """
  The message with this id, or nil. The `from_message` hook for stated facts
  (`Dossier.bank_stated_fact/2`): a caller quotes a message by reference, never
  by paraphrase.
  """
  def message(id), do: Repo.get(Message, id)

  @doc """
  A thread's messages in the order they were posted. Ordered by id, which is the
  true insertion order under §4's single writer — never by `created_at`, whose
  second resolution can tie.
  """
  def thread_messages(%Thread{} = thread) do
    Repo.all(from m in Message, where: m.thread_id == ^thread.id, order_by: [asc: m.id])
  end

  @doc """
  A thread's most recent messages, capped, in chat order (oldest of the window
  first) — CHATTER for the board (§4), which shows the tail, not the whole history.
  """
  def recent_messages(%Thread{} = thread, limit \\ 10) do
    from(m in Message, where: m.thread_id == ^thread.id, order_by: [desc: m.id], limit: ^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  The most recent message on `thread_id` authored by the configured operator (config `:operator`,
  case-insensitive — see `Dossier.bank_stated_fact/2`), or nil. Opening-turn source: a
  freshly spawned per-thread window is woken with the operator's own words, verbatim, never an
  agent's paraphrase.
  """
  def latest_operator_message(thread_id) do
    Repo.one(
      from m in Message,
        where: m.thread_id == ^thread_id and fragment("lower(?)", m.author) == ^operator(),
        order_by: [desc: m.id],
        limit: 1
    )
  end

  @doc """
  The first message on `thread_id` authored by the configured operator, or nil: the ask a thread
  was opened with, kept whole in the brief after it has scrolled out of the recent tail.
  """
  def opening_operator_message(thread_id) do
    Repo.one(
      from m in Message,
        where: m.thread_id == ^thread_id and fragment("lower(?)", m.author) == ^operator(),
        order_by: [asc: m.id],
        limit: 1
    )
  end

  @doc """
  Is `author` the configured operator (config `:operator`, case-insensitive)? The one
  operator-detection seam — renderers color by it, `latest_operator_message/1` queries by it,
  `Dossier.bank_stated_fact/2` gates `stated` provenance on it.
  """
  def operator?(author) when is_binary(author), do: String.downcase(author) == operator()
  def operator?(_author), do: false

  defp operator, do: :server |> Application.get_env(:operator, "andrew") |> String.downcase()

  @doc """
  Recent messages ACROSS all threads — the Comms rollup feed (a "slack for agents" timeline, not
  one channel). Each row carries its `thread_id` + `thread_title` so the surface can group the
  feed by thread. Newest `limit` messages, returned oldest-first (chat order, newest at the
  bottom like a chat log).
  """
  def recent_across(limit \\ 50) do
    from(m in Message,
      join: t in Thread,
      on: t.id == m.thread_id,
      order_by: [desc: m.id],
      limit: ^limit,
      select: %{
        id: m.id,
        thread_id: m.thread_id,
        thread_title: t.title,
        author: m.author,
        body: m.body,
        reply_to: m.reply_to,
        created_at: m.created_at
      }
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc """
  The Comms chorus as THREAD BLOCKS — one entry per OPEN **project** thread, each with its recent messages
  (chat order within), ordered by most-recent-activity FIRST. Every open project thread appears,
  including one with no messages yet (a fresh thread you just spawned onto) — so the feed and the
  ↑/↓ navigator share ONE order and every focusable thread is visible. The machine-scope thread
  (the Tlön coworker) is excluded — it's a meta thread, not project work; reach it via the Tlön
  space. `[%{thread, messages}]`.

  Ordered by message **id**, never `created_at` — its second resolution ties (§4), which would
  make the feed order flap. Threads with messages lead (newest message first); threads with none
  trail (newest thread first), so a just-made quiet thread is visible at the bottom, not lost.
  """
  def chorus(per_thread \\ 20) do
    thread_blocks(from(t in Thread, where: t.state == "open" and t.scope == ^@project_scope), per_thread)
  end

  # The threads of `query` as `[%{thread, messages}]` blocks: each carries its last `per_thread`
  # messages (chat order within), most-recent-activity first.
  defp thread_blocks(query, per_thread) do
    by_thread = 300 |> recent_across() |> Enum.group_by(& &1.thread_id)

    query
    |> Repo.all()
    |> Enum.map(fn t ->
      messages = by_thread |> Map.get(t.id, []) |> Enum.take(-per_thread)
      %{thread: t, messages: messages}
    end)
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  # {tier, id}: threads WITH messages (tier 1) rank above empty ones (tier 0); within a tier the
  # higher id (newest message, else newest thread) leads. A total order, no created_at tie.
  defp sort_key(%{messages: [], thread: %Thread{id: id}}), do: {0, id}
  defp sort_key(%{messages: messages}), do: {1, List.last(messages).id}

  @doc """
  Staff `thread_id` with the agent named `handle` — a resolve-then-assign in one call. `{:ok, thread}` on success; `{:error,
  :no_agent}` when the handle has never registered (a coworker not yet staffed — a no-op, not a
  crash); `{:error, :no_thread}` when the thread id doesn't resolve; `{:error,
  :manager_leads_no_workline}` when `handle` is the workspace's manager (a meta seat, who staffs
  work and never writes it) and the thread is a workline.
  """
  def assign_lead(thread_id, handle) do
    with %Agent{} = agent <- Staff.agent_by_name(handle) || {:error, :no_agent},
         %Thread{} = thread <- thread(thread_id) || {:error, :no_thread},
         false <- manager_on_workline?(thread, handle) and {:error, :manager_leads_no_workline} do
      Staff.assign(thread, agent)
    end
  end

  @doc "Whether `handle` sits on `thread`'s workspace bench as a meta seat (the manager) and the thread is a workline."
  def manager_on_workline?(%Thread{stage: nil}, _handle), do: false
  def manager_on_workline?(%Thread{workspace_id: nil}, _handle), do: false

  def manager_on_workline?(%Thread{workspace_id: ws}, handle) do
    ws
    |> Server.Workspaces.bench()
    |> Enum.any?(&(&1.name == handle and Server.Profiles.meta?(Server.Profiles.roster_entry(&1).archetype)))
  end

  @doc "The name of the agent staffed on `thread_id` (its lead), or nil if unassigned/absent."
  def thread_lead(thread_id) do
    Repo.one(
      from t in Thread,
        join: a in Agent,
        on: a.id == t.agent_id,
        where: t.id == ^thread_id,
        select: a.name
    )
  end
end
