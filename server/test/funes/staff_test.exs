defmodule Server.StaffTest do
  # Step 3: the agent, the session, and staffing a thread (aleph §3, §9.3). An
  # AGENT is the durable identity + profile (Sandra, Robert) — a row that outlives
  # everything. A SESSION is an ephemeral running instance of an agent, in a pane,
  # on an engine, working one thread; it compacts and dies (§10). This step builds
  # the data model for that distinction plus assignment — never presence, routing,
  # or the wake (all §3b/§10-deferred). The DB is the bus (§10): every assertion
  # reads back through SQLite, never through the struct we were handed.
  use ExUnit.Case, async: false

  alias Server.Agent
  alias Server.Channel
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Thread

  # This suite shares one DB (no sandbox, like step 2), but unlike thread/message,
  # `agent.name` is UNIQUE — so a reused name across tests would collide. Isolate
  # each test by clearing the domain rows first (FK-safe, via the shared helper).
  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "register_agent/1 — the durable identity" do
    test "registers an agent that reads back as a durable row, full profile intact" do
      # Sandra: fat everything (aleph §3) — the whole five-axis profile round-trips.
      {:ok, agent} =
        Staff.register_agent(%{
          name: "Sandra",
          mandate: "own the review queue end to end",
          engine: "deep reasoning",
          context: "the review scope and its scoped facts",
          sight: "repos, the PR API, the web",
          hands: "comment, request changes, merge on my call",
          trust: "acts without asking below a merge",
          sandbox: "local with grants"
        })

      reloaded = Repo.get!(Agent, agent.id)
      assert reloaded.name == "Sandra"
      assert reloaded.mandate == "own the review queue end to end"
      assert reloaded.engine == "deep reasoning"
      assert reloaded.context == "the review scope and its scoped facts"
      assert reloaded.sight == "repos, the PR API, the web"
      assert reloaded.hands == "comment, request changes, merge on my call"
      assert reloaded.trust == "acts without asking below a merge"
      assert reloaded.sandbox == "local with grants"
      assert %DateTime{} = reloaded.created_at
    end

    test "a thin agent (Robert) is valid — the five axes are optional" do
      # Robert: thin everything, no Hands, short Trust, locked Sandbox (aleph §3).
      # A name, a mandate, and an engine are the only required fields.
      {:ok, agent} =
        Staff.register_agent(%{
          name: "Robert",
          mandate: "read-only reviewer, fresh eyes",
          engine: "not the weights under review"
        })

      reloaded = Repo.get!(Agent, agent.id)
      assert reloaded.name == "Robert"
      assert reloaded.hands == nil
      assert reloaded.sight == nil
    end

    test "name, mandate, and engine are required" do
      assert {:error, cs} = Staff.register_agent(%{mandate: "m", engine: "e"})
      assert %{name: _} = errors_on(cs)

      assert {:error, cs} = Staff.register_agent(%{name: "n", engine: "e"})
      assert %{mandate: _} = errors_on(cs)

      # An agent must be powerable by an engine (§3) — the strength requirement is
      # required. (It holds a strength like "deep reasoning", never a model name.)
      assert {:error, cs} = Staff.register_agent(%{name: "n", mandate: "m"})
      assert %{engine: _} = errors_on(cs)
    end

    test "a name is unique — it attaches to a role and outlives the workspace (§5b)" do
      {:ok, _} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})

      # The DB's UNIQUE index is the guard; register surfaces its rejection as a
      # tidy changeset error (a duplicate name is a plausible caller mistake, unlike
      # an orphan FK which is a bug that raises).
      assert {:error, cs} = Staff.register_agent(%{name: "Sandra", mandate: "m2", engine: "e2"})
      assert %{name: _} = errors_on(cs)
    end

    test "agent_by_name/1 returns the durable row" do
      {:ok, _} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      assert %Agent{name: "Sandra"} = Staff.agent_by_name("Sandra")
      assert Staff.agent_by_name("Nobody") == nil
    end
  end

  describe "assigning an agent to a thread" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      %{thread: thread, agent: agent}
    end

    test "assign/2 sets the thread's agent, read back through SQLite", %{
      thread: thread,
      agent: agent
    } do
      {:ok, _} = Staff.assign(thread, agent)
      assert Repo.get!(Thread, thread.id).agent_id == agent.id
    end

    test "a thread has 0..1 agent — assigning replaces, unassign clears to NULL", %{
      thread: thread,
      agent: agent
    } do
      {:ok, other} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})

      {:ok, _} = Staff.assign(thread, agent)
      {:ok, _} = Staff.assign(thread, other)
      assert Repo.get!(Thread, thread.id).agent_id == other.id

      {:ok, _} = Staff.unassign(thread)
      assert Repo.get!(Thread, thread.id).agent_id == nil
    end

    test "threads_for/1 returns an agent's threads, scoped to it", %{
      thread: thread,
      agent: agent
    } do
      {:ok, thread2} = Channel.open_thread(%{title: "review PR 400"})
      {:ok, other} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})
      {:ok, others} = Channel.open_thread(%{title: "someone else's"})

      {:ok, _} = Staff.assign(thread, agent)
      {:ok, _} = Staff.assign(thread2, agent)
      {:ok, _} = Staff.assign(others, other)

      # Scoped to the agent, and newest first (desc id) — the order is the contract,
      # so assert it unsorted rather than laundering it through Enum.sort.
      titles = agent |> Staff.threads_for() |> Enum.map(& &1.title)
      assert titles == ["review PR 400", "review PR 329"]
    end

    test "a thread cannot reference an agent that does not exist — SQLite refuses it", %{
      thread: thread
    } do
      # The FK is the DB's own guard (§10), not a mirrored app-side check. A bogus
      # agent_id is refused by SQLite itself and raises, exactly as an orphan
      # message FK does in step 2.
      assert_raise Ecto.ConstraintError, fn ->
        thread |> Ecto.Changeset.change(agent_id: 999_999) |> Repo.update()
      end
    end
  end

  describe "sessions — the ephemeral instance" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      %{thread: thread, agent: agent}
    end

    test "start_session/1 records agent × thread × opaque ref, reads back durable", %{
      thread: thread,
      agent: agent
    } do
      {:ok, session} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w4H:pJ"})

      reloaded = Repo.get!(Session, session.id)
      assert reloaded.agent_id == agent.id
      assert reloaded.thread_id == thread.id
      # The pane handle is stored verbatim and opaque — never a cached copy of
      # its properties (§2's one seam).
      assert reloaded.pane_ref == "w4H:pJ"
      assert %DateTime{} = reloaded.started_at
      assert reloaded.ended_at == nil
    end

    test "an agent and a thread are required to start a session", %{thread: thread, agent: agent} do
      assert {:error, cs} = Staff.start_session(%{thread_id: thread.id})
      assert %{agent_id: _} = errors_on(cs)

      assert {:error, cs} = Staff.start_session(%{agent_id: agent.id})
      assert %{thread_id: _} = errors_on(cs)
    end

    test "a session cannot reference a non-existent agent or thread — SQLite refuses it", %{
      thread: thread,
      agent: agent
    } do
      assert_raise Ecto.ConstraintError, fn ->
        Staff.start_session(%{agent_id: 999_999, thread_id: thread.id, pane_ref: "w"})
      end

      assert_raise Ecto.ConstraintError, fn ->
        Staff.start_session(%{agent_id: agent.id, thread_id: 999_999, pane_ref: "w"})
      end
    end

    test "a session stores NO cached property of its pane — only the opaque ref (§2)" do
      # §2's one seam, stated so it cannot be widened: SQLite holds the pane id
      # and never a label, pane list, or status. Asserted as an ALLOWLIST, not a
      # denylist of guessed names — the rule is positive ("only the opaque ref"), so
      # ANY new column trips this, including one no one thought to forbid. Note:
      # last_active_at is OUR OWN presence bookkeeping (§3b), not a cached pane
      # property, so it belongs here.
      assert Session.__schema__(:fields) ==
               [
                 :id,
                 :pane_ref,
                 :started_at,
                 :ended_at,
                 :last_active_at,
                 :agent_id,
                 :thread_id
               ]
    end

    test "session_for_thread/1 finds the live session to jump into, newest first", %{
      thread: thread,
      agent: agent
    } do
      # jump-into-session (§9.3): the candidate is the newest not-yet-ended session
      # for the thread. Liveness itself is asked of the arbiter live (§2), never
      # stored — this only hands over which pane to poke. Sandra and Robert are
      # COWORKERS on the thread — per-(thread, agent) liveness is the invariant, so
      # two agents' live sessions coexist; two of one agent's cannot.
      {:ok, robert} = Staff.register_agent(%{name: "Robert", mandate: "m", engine: "e"})

      {:ok, first} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})

      {:ok, second} =
        Staff.start_session(%{agent_id: robert.id, thread_id: thread.id, pane_ref: "w2"})

      assert Staff.session_for_thread(thread).id == second.id

      {:ok, _} = Staff.end_session(second)
      # The next-newest still-open session becomes the candidate.
      assert Staff.session_for_thread(thread).id == first.id

      {:ok, _} = Staff.end_session(first)
      # All ended — nothing to jump into. Sessions die; you brief a new one (§3b).
      assert Staff.session_for_thread(thread) == nil
    end

    test "a second session for the same (thread, agent) SUPERSEDES the first", %{
      thread: thread,
      agent: agent
    } do
      # The zombie guard (pi doc §4c.2): a crashed pi leaves ended_at NULL, and
      # "reconciliation cannot depend on a clean exit" (§8) — so the replacement's
      # start is what ends the predecessor, in the same transaction. Otherwise the
      # switchboard wakes BOTH panes while the zombie is still warm.
      {:ok, first} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})

      {:ok, second} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w2"})

      assert %DateTime{} = Repo.get!(Session, first.id).ended_at
      assert Repo.get!(Session, second.id).ended_at == nil
      assert Staff.session_for_thread(thread).id == second.id
    end

    test "supersede announces the ended zombie, then the started replacement", %{
      thread: thread,
      agent: agent
    } do
      # The roster is reactive (aleph §4): it must see the zombie leave and the
      # replacement arrive, or IN FLIGHT shows a pane that no longer exists.
      Server.Bus.subscribe_sessions()

      {:ok, first} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})

      first_id = first.id
      assert_receive {:session_started, %Session{id: ^first_id}}

      {:ok, second} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w2"})

      second_id = second.id
      assert_receive {:session_ended, %Session{id: ^first_id}}
      assert_receive {:session_started, %Session{id: ^second_id}}
    end

    test "the DB itself refuses a second live (thread, agent) session", %{
      thread: thread,
      agent: agent
    } do
      # The partial unique index is the guard (§10) — supersede-in-start is
      # convention, and under a concurrent-register race convention loses. A raw
      # write that bypasses start_session is refused by SQLite itself.
      {:ok, _} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w1"})

      assert_raise Ecto.ConstraintError, fn ->
        %{agent_id: agent.id, thread_id: thread.id, pane_ref: "w2"}
        |> Session.start_changeset()
        |> Repo.insert()
      end
    end

    test "end_session/1 stamps ended_at, read back through SQLite", %{
      thread: thread,
      agent: agent
    } do
      {:ok, session} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w"})

      {:ok, ended} = Staff.end_session(session)
      assert %DateTime{} = ended.ended_at
      assert %DateTime{} = Repo.get!(Session, session.id).ended_at
    end
  end

  describe "touch_sessions/2 — warmth's one write path" do
    # Warmth (§3b) must have exactly ONE write semantic — forward-only — shared by
    # the switchboard's delivery/authoring bumps and the MCP channel's per-call
    # measurement. Two implementations of "bump last_active_at" would be two
    # writers that drift (§2), so the semantic lives here and everyone delegates.
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})

      {:ok, session} =
        Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "w"})

      %{session: session}
    end

    test "a later stamp advances; an earlier one is ignored (forward-only)", %{session: session} do
      base = Repo.get!(Session, session.id).last_active_at
      later = DateTime.shift(base, minute: 10)

      :ok = Staff.touch_sessions([session.id], later)
      assert Repo.get!(Session, session.id).last_active_at == later

      # A backlog drain replaying an old message must never move warmth BACKWARD —
      # a session that acted at T is warm as of T, whatever else it did before.
      earlier = DateTime.shift(later, minute: -20)
      :ok = Staff.touch_sessions([session.id], earlier)
      assert Repo.get!(Session, session.id).last_active_at == later
    end

    test "fills a NULL last_active_at", %{session: session} do
      import Ecto.Query

      Repo.update_all(from(s in Session, where: s.id == ^session.id), set: [last_active_at: nil])

      stamp = DateTime.truncate(DateTime.utc_now(), :second)
      :ok = Staff.touch_sessions([session.id], stamp)
      assert Repo.get!(Session, session.id).last_active_at == stamp
    end

    test "an empty id list is a no-op" do
      assert :ok = Staff.touch_sessions([], DateTime.truncate(DateTime.utc_now(), :second))
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
