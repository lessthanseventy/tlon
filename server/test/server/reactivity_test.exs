defmodule Server.ReactivityTest do
  # Every write announces itself (aleph §5): the board reacts to typed events on
  # focused topics instead of polling. The write is durable first (§10); the
  # broadcast is the nudge. Here we subscribe and assert each context emits.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Channel
  alias Server.Dossier
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "thread lifecycle → funes:threads and the thread topic" do
    test "open, assign, close each broadcast" do
      Bus.subscribe_threads()
      {:ok, thread} = Channel.open_thread(%{title: "review PR 329"})
      assert_receive {:thread_opened, %{id: id}} when id == thread.id

      Bus.subscribe_thread(thread.id)
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      {:ok, _} = Staff.assign(thread, agent)
      # Assignment lands on both the list topic and the thread's own topic.
      assert_receive {:thread_assigned, %{id: id}} when id == thread.id
      assert_receive {:thread_assigned, %{id: id}} when id == thread.id

      {:ok, _} = Channel.close_thread(thread)
      assert_receive {:thread_closed, %{id: id}} when id == thread.id
    end
  end

  describe "session lifecycle → funes:sessions and the thread topic" do
    test "start and end each broadcast" do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      {:ok, agent} = Staff.register_agent(%{name: "Sandra", mandate: "m", engine: "e"})
      Bus.subscribe_sessions()

      {:ok, session} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id})
      assert_receive {:session_started, %{id: id}} when id == session.id

      {:ok, _} = Staff.end_session(session)
      assert_receive {:session_ended, %{id: id}} when id == session.id
    end
  end

  describe "dossier writes → the thread topic (feeds LEARNINGS/SHIPPED/BLOCKERS)" do
    setup do
      {:ok, thread} = Channel.open_thread(%{title: "t"})
      Bus.subscribe_thread(thread.id)
      %{thread: thread}
    end

    test "fact, event, issue raise and resolve each broadcast", %{thread: thread} do
      {:ok, fact} =
        Dossier.bank_fact(%{
          thread_id: thread.id,
          kind: "learned",
          text: "x",
          provenance: "derived"
        })

      assert_receive {:fact_banked, %{id: id}} when id == fact.id

      {:ok, event} = Dossier.record_event(%{thread_id: thread.id, kind: "work_landed"})
      assert_receive {:event_recorded, %{id: id}} when id == event.id

      {:ok, issue} = Dossier.raise_issue(%{thread_id: thread.id, summary: "s"})
      assert_receive {:issue_raised, %{id: id}} when id == issue.id

      {:ok, _} = Dossier.resolve_issue(issue)
      assert_receive {:issue_resolved, %{id: id}} when id == issue.id
    end
  end
end
