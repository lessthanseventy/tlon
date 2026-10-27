defmodule Server.AuthorshipTest do
  # #679: the one place "who wrote it" is rendered. A stamped row names its seat, pane and session
  # (what a denial is checked against); a NULL says "session unknown", never a guess.
  use ExUnit.Case, async: false

  alias Server.Authorship
  alias Server.Channel
  alias Server.Staff

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "qa pass"})
    {:ok, agent} = Staff.register_agent(%{name: "nolan", mandate: "m", engine: "e"})
    %{thread: thread, agent: agent}
  end

  test "label/2 names seat, pane and session", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    assert Authorship.label("nolan", s.id) == "nolan · pane t#{thread.id} %9 · session #{s.id}"
  end

  test "an ended session still renders", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    {:ok, _} = Staff.end_session(s)
    assert Authorship.label("nolan", s.id) == "nolan · pane t#{thread.id} %9 · session #{s.id}"
  end

  test "no pane drops the pane segment", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id})
    assert Authorship.label("nolan", s.id) == "nolan · session #{s.id}"
  end

  test "nil and a vanished session are unknown" do
    assert Authorship.label("tlon", nil) == "tlon · session unknown"
    assert Authorship.label("nolan", 999_999) == "nolan · session unknown"
  end

  test "session_label/1 is the same string without the author", %{thread: thread, agent: agent} do
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    assert Authorship.session_label(s.id) == "pane t#{thread.id} %9 · session #{s.id}"
    assert Authorship.session_label(nil) == "session unknown"
  end

  describe "rendered by Server.MCP.Brief" do
    alias Server.MCP.Brief

    setup %{thread: thread, agent: agent} do
      {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
      %{session: s, label: "pane t#{thread.id} %9 · session #{s.id}"}
    end

    test "message/1: a stamped row names its session, a NULL one says unknown", ctx do
      {:ok, m} = Channel.post(%{thread_id: ctx.thread.id, author: "nolan", body: "x"}, session_id: ctx.session.id)
      assert Brief.message(m)["by"] == "nolan · #{ctx.label}"
      {:ok, old} = Channel.post(%{thread_id: ctx.thread.id, author: "nolan", body: "y"})
      assert Brief.message(old)["by"] == "nolan · session unknown"
    end

    test "ticket/1: filed_by", ctx do
      {:ok, ws} = Server.Workspaces.register(%{name: "Work"})
      {:ok, t} = Server.Tickets.file(%{workspace_id: ws.id, title: "t"}, session_id: ctx.session.id)
      assert Brief.ticket(t)["filed_by"] == ctx.label
      {:ok, old} = Server.Tickets.file(%{workspace_id: ws.id, title: "u"})
      assert Brief.ticket(old)["filed_by"] == "session unknown"
    end

    test "check/1: a qa by check names the seat; any other check its session", ctx do
      {:ok, qa} =
        Server.Dossier.record_check(%{thread_id: ctx.thread.id, cmd: "qa by nolan", exit: 0},
          session_id: ctx.session.id
        )

      assert Brief.check(qa)["by"] == "nolan · #{ctx.label}"

      {:ok, plain} =
        Server.Dossier.record_check(%{thread_id: ctx.thread.id, cmd: "mix test", exit: 0}, session_id: ctx.session.id)

      assert Brief.check(plain)["by"] == ctx.label
      {:ok, old} = Server.Dossier.record_check(%{thread_id: ctx.thread.id, cmd: "qa by nolan", exit: 1})
      assert Brief.check(old)["by"] == "nolan · session unknown"
    end
  end
end
