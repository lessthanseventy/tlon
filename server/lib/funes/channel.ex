defmodule Server.Channel do
  @moduledoc """
  The coordination spine (spec §5b, console §2/§9.2): threads and the messages on
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
  alias Server.Habit
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
    attrs
    |> Map.put_new_lazy(:workspace_id, &Server.Bootstrap.default_workspace_id/0)
    |> Thread.open_changeset()
    |> Repo.insert()
    |> Server.Bus.announce(:thread_opened)
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
      {:ok, message}
    end
  end

  @doc "Close a thread. Its messages are untouched — history outlives the close."
  def close_thread(%Thread{} = thread) do
    thread
    |> Thread.state_changeset("closed")
    |> Repo.update()
    |> Server.Bus.announce(:thread_closed)
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

  # The transactional body: unlink the surviving rows, delete the thread-scoped ones, then the row.
  defp purge_thread(thread) do
    for schema <- [Fact, Issue, Event] do
      Repo.update_all(from(r in schema, where: r.thread_id == ^thread.id), set: [thread_id: nil])
    end

    for schema <- [Message, Todo, Question, Session] do
      Repo.delete_all(from(r in schema, where: r.thread_id == ^thread.id))
    end

    Repo.delete!(thread)
  end

  @doc "Whether `thread` IS the root machine thread — the standing coworkers' permanent home.
  Public: delete_thread refuses it here, and Workline.promote refuses to track it (slice B)."
  def root_machine_thread?(%Thread{scope: @machine_scope} = thread) do
    case machine_thread() do
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

  @doc ~s"""
  The ROOT machine thread — the OLDEST open machine-scope thread, or nil. The founding machine
  thread: the standing coworkers' permanent home and the Orbis Tertius meta thread (design:
  `docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md`). Also the find-or-create lookup for
  the Tlön machine coworker, so it reuses a persistent thread across console restarts.

  Oldest, NOT newest: every staffed leaf thread is machine-scope too, so a `[desc: t.id]`
  "latest machine thread" would return a leaf, not the root. Leaves are always newer
  than the root, so `[asc: t.id]` returns the root and only the root (until it is closed, which
  rotation/`clear-machine-threads` must not do).
  """
  def machine_thread do
    Repo.one(
      from t in Thread,
        where: t.state == "open" and t.scope == ^@machine_scope and is_nil(t.stage),
        order_by: [asc: t.id],
        limit: 1
    )
  end

  @doc """
  Every OPEN machine-scope thread, oldest-first (the root leads) — the leaf set the Orbis Tertius
  meta agent reads across (`Server.Board.machine_overview/0`). Open-only: the synthesis is over work
  in flight, not the closed history.
  """
  def open_machine_threads do
    # TRACKED leaves stay in (reshape slice C): auto-promote gives a working leaf a stage on
    # its first commit — filtering on `is_nil(stage)` here made exactly the leaves doing real
    # work vanish from the meta agent's overview. Only ROOT resolution (machine_thread/0)
    # still excludes staged threads: the root is never a work item.
    Repo.all(
      from t in Thread,
        where: t.state == "open" and t.scope == ^@machine_scope,
        order_by: [asc: t.id]
    )
  end

  @doc """
  STAFFED, OPEN machine-scope threads — the `ensure_thread_sessions` candidate list (console
  cockpit.ex): every open machine-scope thread with a lead, `%{id, lead, title}` per thread
  (`lead` is the staffed agent's name; the join makes it never nil). Open-only (Slice F): the
  cockpit tears a leaf's window down when its thread closes, so a closed thread in this list
  would be killed and respawned every render. No ordering guarantee — the cockpit does its own
  dedup against live tmux windows and its own retry backoff.
  """
  def staffed_machine_threads do
    Repo.all(
      from t in Thread,
        join: a in Agent,
        on: a.id == t.agent_id,
        where: t.scope == ^@machine_scope and t.state == "open" and not is_nil(t.agent_id),
        select: %{id: t.id, lead: a.name, title: t.title}
    )
  end

  @doc """
  Delete every MACHINE-scope thread and everything hanging off it — the clean-slate reset behind
  `mise run console:clear-machine-threads` (old machine threads are disposable).

  Every table with a `thread_id` FK must be cleared before the threads themselves: SQLite's FKs
  are `NO ACTION`, so a single surviving child row rejects the whole thread delete. Two wrinkles
  in the child sweep:

    * `fact` references `session` (`fact.source_session_id`), so facts must be deleted BEFORE
      sessions, or the session delete trips that FK.
    * `habit` is machine-WIDE and only cites the proposing thread as nullable provenance
      (`source_thread_id`) — we null that pointer instead of deleting the habit, so a clean-slate
      never discards learned behavior.

  If a new table gains a `thread_id` FK, add it to the sweep below. All of it runs in one
  transaction. Returns `{:ok, %{threads: n, messages: m}}` so the caller can report what it
  cleared. NEVER touches project-scope threads.
  """
  def clear_machine_threads do
    Repo.transaction(fn ->
      ids = Repo.all(from t in Thread, where: t.scope == ^@machine_scope, select: t.id)

      Repo.update_all(from(h in Habit, where: h.source_thread_id in ^ids), set: [source_thread_id: nil])

      # Fact before Session (fact.source_session_id FK); the rest only reference thread_id.
      for schema <- [Fact, Session, Event, Issue, Question, Todo] do
        Repo.delete_all(from r in schema, where: r.thread_id in ^ids)
      end

      {messages, _} = Repo.delete_all(from m in Message, where: m.thread_id in ^ids)
      {threads, _} = Repo.delete_all(from t in Thread, where: t.id in ^ids)
      %{threads: threads, messages: messages}
    end)
  end

  @doc """
  ALL machine-scope threads as THREAD BLOCKS — console's Tlön machine-chat surface.
  Like `chorus/1` but scoped to `machine` and WITHOUT the open-only filter: a rotated (closed)
  machine thread must still surface as history, so the chat can fold it below the current one.
  Each block carries the thread's recent messages (chat order within), most-recent-activity FIRST.
  `[%{thread, messages}]`.
  """
  def machine_threads(per_thread \\ 20) do
    by_thread = 300 |> recent_across() |> Enum.group_by(& &1.thread_id)

    # Worklines stay IN the chat surface — the spec interview happens on the workline thread.
    # Only ROOT resolution (machine_thread/0) and the surveyor's leaf set exclude them.
    from(t in Thread, where: t.scope == ^@machine_scope)
    |> Repo.all()
    |> Enum.map(fn t ->
      messages = by_thread |> Map.get(t.id, []) |> Enum.take(-per_thread)
      %{thread: t, messages: messages}
    end)
    |> Enum.sort_by(&sort_key/1, :desc)
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
  Is `author` the configured operator (config `:operator`, case-insensitive)? The one
  operator-detection seam — renderers color by it, `latest_operator_message/1` queries by it.
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
    by_thread = 300 |> recent_across() |> Enum.group_by(& &1.thread_id)

    from(t in Thread, where: t.state == "open" and t.scope == ^@project_scope)
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
  Staff `thread_id` with the agent named `handle` — the console machine-chat staffing call, a single
  clean boundary crossing over a resolve-then-assign. `{:ok, thread}` on success; `{:error,
  :no_agent}` when the handle has never registered (a coworker not yet staffed — a no-op, not a
  crash); `{:error, :no_thread}` when the thread id doesn't resolve.
  """
  def assign_lead(thread_id, handle) do
    with %Agent{} = agent <- Staff.agent_by_name(handle) || {:error, :no_agent},
         %Thread{} = thread <- thread(thread_id) || {:error, :no_thread} do
      Staff.assign(thread, agent)
    end
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
