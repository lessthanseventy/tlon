defmodule Server.ChannelTest do
  # Step 2: the thread + message spine (aleph §9.2, spec §5b). The thread is the
  # atom of work; the message is the channel and §4's capture path — a message a
  # participant writes is already a durable row. The DB is the bus (§10): every
  # assertion here reads back through SQLite, never through in-memory state.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Staff
  alias Server.Thread
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "open_thread/1" do
    test "opens a thread that reads back as a durable, open row" do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})

      # Read it back from SQLite, not from the struct we were handed — the row is
      # the truth, the struct is a copy.
      reloaded = Repo.get!(Thread, thread.id)
      assert reloaded.title == "review PR 329"
      assert reloaded.state == "open"
      assert reloaded.scope == "project"
      assert %DateTime{} = reloaded.created_at
    end

    test "a machine-scope thread opens with scope=\"machine\" (the Tlön coworker)" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      assert Repo.get!(Thread, thread.id).scope == "machine"
    end
  end

  describe "post/1 — the capture path" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      %{thread: thread}
    end

    test "a body carrying an obvious credential is refused — the channel is a capture path too",
         %{thread: thread} do
      {:error, changeset} =
        Channel.post(%{
          thread_id: thread.id,
          author: "sandra",
          body: "use AKIAIOSFODNN7EXAMPLE for the deploy"
        })

      assert {"looks like a secret (AWS access key); tlon does not store credentials", _} =
               changeset.errors[:body]

      # and nothing persisted — the guard fires before the row exists, not one layer later
      assert Repo.aggregate(Message, :count, :id) == 0
    end

    test "a posted message is immediately a durable row (§4/§5b capture path)", %{thread: thread} do
      {:ok, message} =
        Channel.post(%{thread_id: thread.id, author: "stakeholder", body: "look at this"})

      # The row must exist in SQLite, not just in the struct we hold — §10, the DB
      # is the bus. Re-read it.
      reloaded = Repo.get!(Message, message.id)
      assert reloaded.thread_id == thread.id
      assert reloaded.author == "stakeholder"
      assert reloaded.body == "look at this"
      assert %DateTime{} = reloaded.created_at
    end

    test "a thread and a body are the only required fields (§5b)", %{thread: thread} do
      assert {:error, changeset} = Channel.post(%{thread_id: thread.id, author: "sandra"})
      assert %{body: _} = errors_on(changeset)

      # Missing author (a message has a speaker).
      assert {:error, changeset} = Channel.post(%{thread_id: thread.id, body: "hi"})
      assert %{author: _} = errors_on(changeset)

      # Missing thread — a message with no thread is meaningless.
      assert {:error, changeset} = Channel.post(%{author: "sandra", body: "hi"})
      assert %{thread_id: _} = errors_on(changeset)
    end

    test "a message cannot reference a thread that does not exist — SQLite itself refuses it" do
      # The FK is the DB's own guard (§10): not a mirrored app-side check that
      # could race or go stale. An orphan write is refused by SQLite, so it raises
      # rather than returning a tidy changeset — proving the enforcement is real.
      assert_raise Ecto.ConstraintError, fn ->
        Channel.post(%{thread_id: 999_999, author: "sandra", body: "ghost"})
      end
    end
  end

  describe "delivered ≠ read (§5b.3)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})
      {:ok, message} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "hi"})
      %{message: message}
    end

    test "a freshly posted message is undelivered — the sender cannot assert delivery", %{
      message: message
    } do
      assert message.delivered_at == nil
      assert Repo.get!(Message, message.id).delivered_at == nil
    end

    test "a sender cannot fake delivery by smuggling delivered_at through post/1" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})

      {:ok, message} =
        Channel.post(%{
          thread_id: thread.id,
          author: "sandra",
          body: "trust me it's read",
          delivered_at: ~U[2020-01-01 00:00:00Z]
        })

      # The forged stamp is ignored: post/1 does not cast delivered_at at all.
      assert Repo.get!(Message, message.id).delivered_at == nil
    end

    # Delivery-stamping is the switchboard's atomic claim, tested in
    # Server.SwitchboardTest ("marks delivered once the addressee was woken"). The
    # channel's own contract here is only that a sender cannot assert it.

    test "there is no `read` column — nothing can prove a read, so it does not exist" do
      # §5b.3: a column that could only ever lie must not exist. Assert the schema
      # has no field that would tempt a sender-written 'read' receipt.
      refute :read in Message.__schema__(:fields)
      refute :read_at in Message.__schema__(:fields)
    end
  end

  describe "reading a thread" do
    test "messages come back in the order they were posted" do
      {:ok, thread} = Channel.open_thread(%{title: "an argument"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "first"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "robert", body: "second"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "third"})

      bodies = thread |> Channel.thread_messages() |> Enum.map(& &1.body)
      assert bodies == ["first", "second", "third"]
    end

    test "a thread's messages are scoped to it, not another thread's" do
      {:ok, t1} = Channel.open_thread(%{title: "one"})
      {:ok, t2} = Channel.open_thread(%{title: "two"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "a", body: "mine"})
      {:ok, _} = Channel.post(%{thread_id: t2.id, author: "b", body: "theirs"})

      assert t1 |> Channel.thread_messages() |> Enum.map(& &1.body) == ["mine"]
    end

    test "open_threads/0 returns open PROJECT threads and omits closed and machine-scope ones" do
      {:ok, open} = Channel.open_thread(%{title: "still open"})
      {:ok, done} = Channel.open_thread(%{title: "finished"})
      {:ok, _machine} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _} = Channel.close_thread(done)

      titles = Enum.map(Channel.open_threads(), & &1.title)
      assert open.title in titles
      refute done.title in titles
      refute "Tlön" in titles
    end

    test "machine_thread/0 returns the ROOT (oldest open) machine thread, or nil (find-or-create)" do
      assert Channel.machine_thread() == nil

      {:ok, root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      assert Channel.machine_thread().id == root.id

      # A newer machine thread is a staffed LEAF (B1.4), not the root: the root is the oldest and
      # stays the root. (A [desc: id] "latest" query would wrongly return the leaf here — the
      # 2026-08-19 regression this guards.)
      {:ok, _leaf} = Channel.open_thread(%{title: "Tlön · leaf", scope: "machine"})
      assert Channel.machine_thread().id == root.id

      # Only if the root itself closes does it fall through to the next-oldest open thread.
      {:ok, _} = Channel.close_thread(root)
      assert Channel.machine_thread().title == "Tlön · leaf"
    end

    test "recent_across/1 — the Comms chorus feed: messages from every thread, each tagged" do
      {:ok, t1} = Channel.open_thread(%{title: "fable review"})
      {:ok, t2} = Channel.open_thread(%{title: "triage inbox"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "andrew", body: "start it"})
      {:ok, _} = Channel.post(%{thread_id: t2.id, author: "Carl", body: "CI is red"})
      {:ok, _} = Channel.post(%{thread_id: t1.id, author: "pi", body: "on it"})

      feed = Channel.recent_across(50)
      # chat order, newest at the bottom, drawn from BOTH threads with the thread title carried
      assert Enum.map(feed, & &1.body) == ["start it", "CI is red", "on it"]
      assert Enum.map(feed, & &1.thread_title) == ["fable review", "triage inbox", "fable review"]
    end

    test "recent_across/1 caps to the newest `limit`, still oldest-first" do
      {:ok, t} = Channel.open_thread(%{title: "chatty"})
      for i <- 1..5, do: Channel.post(%{thread_id: t.id, author: "a", body: "m#{i}"})

      feed = Channel.recent_across(3)
      # the 3 NEWEST (m3,m4,m5), returned oldest-first
      assert Enum.map(feed, & &1.body) == ["m3", "m4", "m5"]
    end

    test "chorus/0 — one block per OPEN project thread, empty ones included; machine-scope excluded" do
      {:ok, quiet} = Channel.open_thread(%{title: "quiet"})
      {:ok, _} = Channel.post(%{thread_id: quiet.id, author: "a", body: "old news"})
      {:ok, fresh} = Channel.open_thread(%{title: "fresh, no messages"})
      {:ok, loud} = Channel.open_thread(%{title: "loud"})
      {:ok, _} = Channel.post(%{thread_id: loud.id, author: "b", body: "latest"})
      {:ok, machine} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: machine.id, author: "pi-machine", body: "meta chatter"})

      blocks = Channel.chorus()
      titles = Enum.map(blocks, & &1.thread.title)

      # every open PROJECT thread has a block — including the one with no messages
      assert "quiet" in titles
      assert "fresh, no messages" in titles
      assert "loud" in titles
      # the machine-scope thread is EXCLUDED from the project chorus, even with messages
      refute "Tlön" in titles
      # most-recent-activity first: loud (newest message) leads; the empty thread trails but is
      # present (visible + navigable), never vanishing
      assert List.first(titles) == "loud"
      assert List.last(titles) == "fresh, no messages"
      # the block carries the thread's own recent messages, chat order
      loud_block = Enum.find(blocks, &(&1.thread.id == loud.id))
      assert Enum.map(loud_block.messages, & &1.body) == ["latest"]
      assert Enum.find(blocks, &(&1.thread.id == fresh.id)).messages == []
    end

    test "machine_threads/0 — one block per MACHINE thread (incl. closed rotations), project excluded" do
      {:ok, m1} = Channel.open_thread(%{title: "Tlön · aug 16", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: m1.id, author: "pi-machine", body: "old turn"})
      {:ok, project} = Channel.open_thread(%{title: "real work"})
      {:ok, _} = Channel.post(%{thread_id: project.id, author: "andrew", body: "not meta"})
      {:ok, m2} = Channel.open_thread(%{title: "Tlön · aug 17", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: m2.id, author: "claude-machine", body: "newest turn"})
      # a rotation closes the older machine thread — it must still surface as history
      {:ok, _} = Channel.close_thread(m1)

      blocks = Channel.machine_threads()
      titles = Enum.map(blocks, & &1.thread.title)

      # both machine threads appear, closed one included; the project thread never does
      assert "Tlön · aug 16" in titles
      assert "Tlön · aug 17" in titles
      refute "real work" in titles
      # most-recent-activity first: the newer machine thread leads
      assert List.first(titles) == "Tlön · aug 17"
      # the block carries the thread's own messages, chat order
      m1_block = Enum.find(blocks, &(&1.thread.id == m1.id))
      assert Enum.map(m1_block.messages, & &1.body) == ["old turn"]
    end
  end

  describe "the lead invariant — every thread opens with a lead (lead-as-manager)" do
    test "a thread opens led by the workspace's builder coworker (registered on demand)" do
      {:ok, ws} =
        Workspaces.register(%{
          name: "led",
          type: "code",
          scope: "machine",
          paths: [],
          roster: [
            %{"archetype" => "surveyor", "name" => "tertius"},
            %{"archetype" => "builder", "name" => "hronir"}
          ]
        })

      assert Staff.agent_by_name("hronir-machine") == nil
      {:ok, thread} = Channel.open_thread(%{title: "needs a lead", workspace_id: ws.id})

      assert Channel.thread_lead(thread.id) == "hronir-machine"
      assert Staff.agent_by_name("hronir-machine"), "the designated lead was registered on demand"
    end

    test "an explicit agent_id is honored over the default" do
      {:ok, ws} =
        Workspaces.register(%{
          name: "led2",
          type: "code",
          scope: "machine",
          paths: [],
          roster: [%{"archetype" => "builder", "name" => "hronir"}]
        })

      {:ok, custom} = Staff.register_agent(%{name: "custom-machine", mandate: "general", engine: "local"})
      {:ok, thread} = Channel.open_thread(%{title: "explicit", workspace_id: ws.id, agent_id: custom.id})

      assert Channel.thread_lead(thread.id) == "custom-machine"
    end

    test "a workspace with an empty roster opens threads leaderless — no crash" do
      {:ok, ws} = Workspaces.register(%{name: "empty", type: "code", scope: "machine", paths: [], roster: []})
      {:ok, thread} = Channel.open_thread(%{title: "no roster", workspace_id: ws.id})

      assert Channel.thread_lead(thread.id) == nil
    end
  end

  describe "workspace-scoped machine threads (the cockpit re-scope)" do
    setup do
      {:ok, wsa} = Workspaces.register(%{name: "wsa", type: "code", scope: "machine", paths: [], roster: []})
      {:ok, wsb} = Workspaces.register(%{name: "wsb", type: "code", scope: "machine", paths: [], roster: []})
      {:ok, wsa: wsa, wsb: wsb}
    end

    test "machine_thread/1 returns the oldest open stage-less root for THAT workspace", %{wsa: wsa, wsb: wsb} do
      {:ok, root_a} = Channel.open_thread(%{title: "a-root", scope: "machine", workspace_id: wsa.id})
      # A newer machine thread in the SAME workspace is a child, not the root.
      {:ok, _child_a} = Channel.open_thread(%{title: "a-child", scope: "machine", workspace_id: wsa.id})
      {:ok, root_b} = Channel.open_thread(%{title: "b-root", scope: "machine", workspace_id: wsb.id})

      assert Channel.machine_thread(wsa.id).id == root_a.id
      assert Channel.machine_thread(wsb.id).id == root_b.id
      # A workspace with no machine thread yet resolves to nil (Bootstrap fills this).
      {:ok, wsc} = Workspaces.register(%{name: "wsc", type: "code", scope: "machine", paths: [], roster: []})
      assert Channel.machine_thread(wsc.id) == nil
    end

    test "machine_threads/1 filters to one workspace; the other's threads are absent", %{wsa: wsa, wsb: wsb} do
      {:ok, _ta} = Channel.open_thread(%{title: "a-thread", scope: "machine", workspace_id: wsa.id})
      {:ok, _tb} = Channel.open_thread(%{title: "b-thread", scope: "machine", workspace_id: wsb.id})

      a_titles = wsa.id |> Channel.machine_threads() |> Enum.map(& &1.thread.title)
      assert "a-thread" in a_titles
      refute "b-thread" in a_titles

      b_titles = wsb.id |> Channel.machine_threads() |> Enum.map(& &1.thread.title)
      assert "b-thread" in b_titles
      refute "a-thread" in b_titles
    end

    test "machine_threads/0 (nil workspace) stays global — both workspaces' threads", %{wsa: wsa, wsb: wsb} do
      {:ok, _ta} = Channel.open_thread(%{title: "a-thread", scope: "machine", workspace_id: wsa.id})
      {:ok, _tb} = Channel.open_thread(%{title: "b-thread", scope: "machine", workspace_id: wsb.id})

      titles = Enum.map(Channel.machine_threads(), & &1.thread.title)
      assert "a-thread" in titles
      assert "b-thread" in titles
    end

    test "workspace_thread_ids/1 returns only that workspace's thread ids", %{wsa: wsa, wsb: wsb} do
      {:ok, ta} = Channel.open_thread(%{title: "a", workspace_id: wsa.id})
      {:ok, _tb} = Channel.open_thread(%{title: "b", workspace_id: wsb.id})

      assert Channel.workspace_thread_ids(wsa.id) == [ta.id]
    end
  end

  describe "the state CHECK is the DB's own guard" do
    test "a thread state outside the closed set is refused by SQLite itself" do
      {:ok, thread} = Channel.open_thread(%{title: "a subject"})

      # No app-side validate_inclusion mirrors this (§2, single source of truth):
      # the closed set lives in the DB CHECK, so a bad state is refused there and
      # raises, exactly as an orphan FK does.
      assert_raise Ecto.ConstraintError, fn ->
        thread |> Thread.state_changeset("garbage") |> Repo.update()
      end
    end

    test "a thread scope outside the closed set is refused by SQLite itself" do
      # The scope CHECK is the same §4 discipline as state: a closed set in the DB.
      assert_raise Ecto.ConstraintError, fn ->
        %Thread{}
        |> Ecto.Changeset.cast(
          %{title: "x", scope: "secret", state: "open", created_at: DateTime.utc_now()},
          [:title, :scope, :state, :created_at]
        )
        |> Repo.insert()
      end
    end
  end

  describe "close_thread/1" do
    test "closes a thread but keeps its messages — history is never taken down with it" do
      {:ok, thread} = Channel.open_thread(%{title: "wrap it up"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "sandra", body: "done"})

      {:ok, closed} = Channel.close_thread(thread)
      assert closed.state == "closed"
      assert Repo.get!(Thread, thread.id).state == "closed"

      # The messages survive the close.
      assert thread |> Channel.thread_messages() |> Enum.map(& &1.body) == ["done"]
    end
  end

  describe "parent/child threads + report-up on close (lead-as-manager, Slice 4D)" do
    test "open_thread accepts a parent_thread_id and reads it back" do
      {:ok, parent} = Channel.open_thread(%{title: "the epic"})
      {:ok, child} = Channel.open_thread(%{title: "a sub-task", parent_thread_id: parent.id})
      assert child.parent_thread_id == parent.id
      assert Repo.get!(Thread, child.id).parent_thread_id == parent.id
    end

    test "closing a child posts a report into the PARENT that @mentions the parent's lead" do
      {:ok, _agent} = Staff.register_agent(%{name: "menard-machine", mandate: "build", engine: "fresh"})
      {:ok, parent} = Channel.open_thread(%{title: "the epic", scope: "machine"})
      {:ok, _} = Channel.assign_lead(parent.id, "menard-machine")
      {:ok, child} = Channel.open_thread(%{title: "the redis cache", parent_thread_id: parent.id})

      {:ok, _} = Channel.close_thread(child)

      [report] = Channel.thread_messages(parent)
      assert report.author == "tlon"
      assert report.body =~ "@menard-machine"
      assert report.body =~ "the redis cache"
      assert report.body =~ "##{child.id}"
    end

    test "closing a child whose parent has NO lead still reports (no @mention, no crash)" do
      {:ok, parent} = Channel.open_thread(%{title: "leaderless epic"})
      {:ok, child} = Channel.open_thread(%{title: "orphan task", parent_thread_id: parent.id})

      {:ok, _} = Channel.close_thread(child)

      [report] = Channel.thread_messages(parent)
      assert report.body =~ "orphan task"
      refute report.body =~ "@"
    end

    test "closing a TOP-LEVEL thread (no parent) posts no report" do
      {:ok, thread} = Channel.open_thread(%{title: "standalone"})
      {:ok, _} = Channel.close_thread(thread)
      assert Channel.thread_messages(thread) == []
    end
  end

  describe "message/1" do
    test "returns the message row, or nil — the from_message hook for stated facts" do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, posted} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "verbatim"})

      assert %Message{body: "verbatim"} = Channel.message(posted.id)
      assert Channel.message(999_999) == nil
    end
  end

  describe "assign_lead/2 — staffing by handle (aleph machine-chat's boundary call)" do
    test "assigns the named agent to the thread when both exist" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _agent} = Staff.register_agent(%{name: "claude-machine", mandate: "m", engine: "e"})

      assert {:ok, updated} = Channel.assign_lead(thread.id, "claude-machine")
      assert updated.id == thread.id
      assert Channel.thread_lead(thread.id) == "claude-machine"
    end

    test "errors, does not crash, when the handle has never registered as an agent" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})

      assert Channel.assign_lead(thread.id, "ghost") == {:error, :no_agent}
      assert Channel.thread_lead(thread.id) == nil
    end

    test "errors when the thread id does not exist" do
      {:ok, _agent} = Staff.register_agent(%{name: "claude-machine", mandate: "m", engine: "e"})

      assert Channel.assign_lead(999_999, "claude-machine") == {:error, :no_thread}
    end
  end

  describe "thread_lead/1" do
    test "returns the name of the agent staffed on the thread" do
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, agent)

      assert Channel.thread_lead(thread.id) == "Sandra"
    end

    test "returns nil for an unassigned thread" do
      {:ok, thread} = Channel.open_thread(%{title: "no lead yet"})
      assert Channel.thread_lead(thread.id) == nil
    end

    test "returns nil for a thread id that does not exist" do
      assert Channel.thread_lead(999_999) == nil
    end
  end

  describe "staffed_machine_threads/0 — B1.4's ensure_thread_sessions candidate list" do
    test "returns machine-scope threads with a lead as %{id, lead, title}" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön · thread A", scope: "machine"})
      {:ok, agent} = Staff.register_agent(%{name: "claude-machine", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, agent)

      assert [%{id: id, lead: "claude-machine", title: "Tlön · thread A"}] = Channel.staffed_machine_threads()
      assert id == thread.id
    end

    test "omits an unstaffed machine thread (no lead yet)" do
      {:ok, _thread} = Channel.open_thread(%{title: "Tlön · unstaffed", scope: "machine"})
      assert Channel.staffed_machine_threads() == []
    end

    test "omits a staffed PROJECT thread — machine scope only" do
      {:ok, thread} = Channel.open_thread(%{title: "project work"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, agent)

      assert Channel.staffed_machine_threads() == []
    end

    test "omits a CLOSED machine thread — the cockpit tears its leaf down on close (Slice F)" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön · rotated", scope: "machine"})
      {:ok, agent} = Staff.register_agent(%{name: "pi-machine", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, agent)
      {:ok, _} = Channel.close_thread(thread)

      assert Channel.staffed_machine_threads() == []
    end
  end

  describe "latest_operator_message/1 — B1.4's opening-turn source" do
    setup do
      Application.put_env(:server, :operator, "andrew")
      on_exit(fn -> Application.delete_env(:server, :operator) end)
    end

    test "returns the most recent message authored by the configured operator" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "first ask"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "pi-machine", body: "on it"})
      {:ok, latest} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "second ask"})

      assert %Message{id: id} = Channel.latest_operator_message(thread.id)
      assert id == latest.id
    end

    test "matches the operator case-insensitively" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, msg} = Channel.post(%{thread_id: thread.id, author: "Andrew", body: "shout-case"})

      assert %Message{id: id} = Channel.latest_operator_message(thread.id)
      assert id == msg.id
    end

    test "returns nil when the thread has no operator message" do
      {:ok, thread} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "pi-machine", body: "solo chatter"})

      assert Channel.latest_operator_message(thread.id) == nil
    end

    test "returns nil for a thread id that does not exist" do
      assert Channel.latest_operator_message(999_999) == nil
    end
  end

  describe "clear_machine_threads/0 — the B1.4 clean-slate reset" do
    test "deletes every machine-scope thread and its messages, leaving project threads alone" do
      {:ok, m1} = Channel.open_thread(%{title: "Tlön · one", scope: "machine"})
      {:ok, _} = Channel.post(%{thread_id: m1.id, author: "andrew", body: "gone"})
      {:ok, m2} = Channel.open_thread(%{title: "Tlön · two", scope: "machine"})
      {:ok, _} = Channel.close_thread(m2)
      {:ok, project} = Channel.open_thread(%{title: "keep me"})
      {:ok, _} = Channel.post(%{thread_id: project.id, author: "andrew", body: "stays"})

      assert {:ok, %{threads: 2, messages: 1}} = Channel.clear_machine_threads()

      assert Channel.machine_threads() == []
      assert Repo.get(Thread, m1.id) == nil
      assert Repo.get(Thread, m2.id) == nil
      assert Repo.get(Thread, project.id)
      assert project |> Channel.thread_messages() |> Enum.map(& &1.body) == ["stays"]
    end

    test "no-op (zero counts) when there are no machine threads" do
      assert {:ok, %{threads: 0, messages: 0}} = Channel.clear_machine_threads()
    end
  end

  describe "delete_thread/1 — the operator's hard delete" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "test clutter"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "hello"})
      %{thread: thread}
    end

    test "removes the thread, its messages, and its thread-scoped rows", %{thread: thread} do
      {:ok, todo} = Server.Dossier.add_todo(%{thread_id: thread.id, text: "a step"})

      assert {:ok, %Thread{}} = Channel.delete_thread(thread)
      assert Repo.get(Thread, thread.id) == nil
      assert Repo.get_by(Message, thread_id: thread.id) == nil
      assert Repo.get(Server.Todo, todo.id) == nil
    end

    test "facts born on the thread survive with the thread link cleared", %{thread: thread} do
      {:ok, fact} =
        Server.Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "kept", provenance: "derived"})

      {:ok, _} = Channel.delete_thread(thread)
      assert Repo.get!(Server.Fact, fact.id).thread_id == nil
    end

    test "the ROOT machine thread is refused — the standing coworkers' home" do
      {:ok, root} = Channel.open_thread(%{title: "Tlön", scope: "machine"})
      {:ok, leaf} = Channel.open_thread(%{title: "a leaf", scope: "machine"})

      assert {:error, :root_machine_thread} = Channel.delete_thread(root)
      assert {:ok, _} = Channel.delete_thread(leaf)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
