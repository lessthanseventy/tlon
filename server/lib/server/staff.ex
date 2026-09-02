defmodule Server.Staff do
  @moduledoc """
  The staff (console §3b): the durable `agent` roster and the ephemeral `session`s
  that run them, plus staffing a thread with an agent. This context owns the
  agent/session data model and assignment; `Server.Channel` keeps owning
  thread/message.

  Deliberately out of scope, and deferred (§3b/§10): presence ("clocked out" is
  derived from the engine, asked live), routing/cover, the night shift, engine
  resolution, and the PubSub wake.
  """
  import Ecto.Query

  alias Server.Agent
  alias Server.Presence
  alias Server.Repo
  alias Server.Session
  alias Server.Thread

  @doc "Register a durable agent. `{:ok, agent}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register_agent(attrs) do
    attrs |> Agent.register_changeset() |> Repo.insert()
  end

  @doc "The durable agent with this name, or nil. Names are unique (§5b)."
  def agent_by_name(name) do
    Repo.get_by(Agent, name: name)
  end

  @doc """
  The IN FLIGHT roster (console §4): every live session across all threads with its
  agent, thread, and a warm/cold flag (`Server.Presence`). Ended sessions omitted,
  newest first — the read the board renders as "who's on the clock."
  """
  def roster do
    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      join: t in Thread,
      on: t.id == s.thread_id,
      where: is_nil(s.ended_at),
      order_by: [desc: s.id],
      select: %{
        agent: a.name,
        thread_id: t.id,
        thread_title: t.title,
        pane_ref: s.pane_ref,
        last_active_at: s.last_active_at
      }
    )
    |> Repo.all()
    |> Enum.map(&Map.put(&1, :warm?, Presence.warm?(&1.last_active_at)))
  end

  @doc """
  Staff a thread with an agent (a thread has 0..1 agent, §3). Assigning again
  replaces the previous agent. Takes a persisted `%Agent{}`, so the FK cannot fire
  here — it is the DB's guard against a raw write of a bogus agent_id (§10).
  """
  def assign(%Thread{} = thread, %Agent{} = agent) do
    thread
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:agent_id, agent.id)
    |> Repo.update()
    |> Server.Bus.announce(:thread_assigned)
  end

  @doc "Clear a thread's agent back to unassigned."
  def unassign(%Thread{} = thread) do
    # force_change, not change: the caller's struct may hold a stale agent_id (it is
    # not reloaded after assign), and change/2 would emit a no-op if the in-memory
    # value already matched. The write must be unconditional.
    thread
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:agent_id, nil)
    |> Repo.update()
  end

  @doc "The threads an agent is staffed on (an agent maps to many threads, §3), newest first."
  def threads_for(%Agent{} = agent) do
    Repo.all(from t in Thread, where: t.agent_id == ^agent.id, order_by: [desc: t.id])
  end

  @doc """
  Start a session — an agent running on a thread in a pane, SUPERSEDING any prior
  live session for the same (thread, agent). A crashed predecessor leaves
  `ended_at` NULL ("reconciliation cannot depend on a clean exit", §8), so the
  replacement's start is what retires the zombie — ended in the same transaction
  that inserts the new row; the partial unique index is the DB's own guard under
  a concurrent race (§10). Both the ended zombie(s) and the start are announced
  AFTER commit — rows are durable before any nudge. Returns `{:ok, session}` or
  `{:error, changeset}` on a missing agent/thread; a non-existent agent or thread
  is refused by SQLite's FK and raises (§10).
  """
  def start_session(attrs) do
    changeset = Session.start_changeset(attrs)
    thread_id = Ecto.Changeset.get_field(changeset, :thread_id)
    agent_id = Ecto.Changeset.get_field(changeset, :agent_id)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    fn ->
      superseded = supersede_live(thread_id, agent_id, now)

      case Repo.insert(changeset) do
        {:ok, session} -> {session, superseded}
        {:error, cs} -> Repo.rollback(cs)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {session, superseded}} ->
        Enum.each(superseded, &Server.Bus.broadcast({:session_ended, &1}))
        Server.Bus.broadcast({:session_started, session})
        {:ok, session}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # End every live session for (thread, agent), returning the ended rows for the
  # post-commit announce. Skipped when either id is missing — the insert's own
  # validation refuses the write and there is nothing to supersede.
  defp supersede_live(thread_id, agent_id, _now) when is_nil(thread_id) or is_nil(agent_id), do: []

  defp supersede_live(thread_id, agent_id, now) do
    live =
      Repo.all(
        from s in Session,
          where: s.thread_id == ^thread_id and s.agent_id == ^agent_id and is_nil(s.ended_at)
      )

    case live do
      [] ->
        []

      sessions ->
        ids = Enum.map(sessions, & &1.id)
        Repo.update_all(from(s in Session, where: s.id in ^ids), set: [ended_at: now])
        Enum.map(sessions, &%{&1 | ended_at: now})
    end
  end

  @doc "End a session — stamp `ended_at`. Sessions die; you brief a new one (§3b)."
  def end_session(%Session{} = session) do
    session |> Session.end_changeset() |> Repo.update() |> Server.Bus.announce(:session_ended)
  end

  @doc """
  Bump sessions' `last_active_at` to `at`, FORWARD-ONLY — warmth's one write path,
  shared by the switchboard (delivery/authoring bumps) and the MCP channel (a tool
  call arriving is measured activity). Two implementations of this semantic would
  be two writers that drift (§2), so it lives here and everyone delegates. A stamp
  earlier than the current value is ignored — a backlog drain replaying an old
  message must never move warmth backward; NULL is filled.
  """
  def touch_sessions([], _at), do: :ok

  def touch_sessions(ids, at) do
    Repo.update_all(
      from(s in Session,
        where: s.id in ^ids and (is_nil(s.last_active_at) or s.last_active_at < ^at)
      ),
      set: [last_active_at: at]
    )

    :ok
  end

  @doc """
  The session to jump into for a thread (§9.3): the newest not-yet-ended session,
  or nil if every session has ended. This hands over which pane to poke — liveness
  itself is asked of the arbiter live (§2), never read from here.
  """
  def session_for_thread(%Thread{} = thread) do
    Repo.one(
      from s in Session,
        where: s.thread_id == ^thread.id and is_nil(s.ended_at),
        order_by: [desc: s.id],
        limit: 1
    )
  end

  @doc """
  The live session for a specific (thread, agent), or nil — the identity a stateless token
  resolves to at read time (`Server.MCP.Tokens`). The partial unique index guarantees at most one
  live session per pair, so this is the current holder of that identity, never a stale one.
  """
  def live_session(thread_id, agent_id) do
    Repo.one(
      from s in Session,
        where: s.thread_id == ^thread_id and s.agent_id == ^agent_id and is_nil(s.ended_at)
    )
  end
end
