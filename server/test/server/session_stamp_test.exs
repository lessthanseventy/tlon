defmodule Server.SessionStampTest do
  # #679: the three write paths take the session as an OPT (`session_id:`), set after cast, so it
  # comes from the connection and never from attrs. A caller that passes nothing (a system author,
  # a non-MCP path) leaves NULL.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Repo
  alias Server.Staff
  alias Server.Tickets
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Work"})
    {:ok, thread} = Channel.open_thread(%{title: "qa pass", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "nolan", mandate: "m", engine: "e"})
    {:ok, s} = Staff.start_session(%{agent_id: agent.id, thread_id: thread.id, pane_ref: "%9"})
    %{thread: thread, session: s, workspace: ws}
  end

  describe "Channel.post/2" do
    test "stamps the opt's session; an attrs key is ignored", %{thread: thread, session: s} do
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "nolan", body: "x", session_id: 99}, session_id: s.id)
      assert Repo.reload!(m).session_id == s.id
    end

    test "no opt leaves NULL", %{thread: thread} do
      {:ok, m} = Channel.post(%{thread_id: thread.id, author: "tlon", body: "x", session_id: 99})
      assert Repo.reload!(m).session_id == nil
    end
  end

  describe "Dossier.record_check/2" do
    test "stamps the opt's session on the event", %{thread: thread, session: s} do
      {:ok, e} = Dossier.record_check(%{thread_id: thread.id, cmd: "c", exit: 0, session_id: 99}, session_id: s.id)
      assert Repo.reload!(e).session_id == s.id
    end

    test "no opt leaves NULL", %{thread: thread} do
      {:ok, e} = Dossier.record_check(%{thread_id: thread.id, cmd: "c", exit: 0})
      assert Repo.reload!(e).session_id == nil
    end
  end

  describe "Tickets.file/2" do
    test "stamps the opt's session; an attrs key is ignored", %{workspace: ws, session: s} do
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "t", session_id: 99}, session_id: s.id)
      assert Repo.reload!(t).session_id == s.id
    end

    test "no opt leaves NULL", %{workspace: ws} do
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "t", session_id: 99})
      assert Repo.reload!(t).session_id == nil
    end
  end
end
