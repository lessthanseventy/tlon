defmodule Server.Office.MarginTest do
  use ExUnit.Case, async: false

  alias Server.Office.Margin

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Margins"})
    {:ok, root} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    {:ok, other} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id})
    %{ws: ws, root: root, other: other}
  end

  test "the workspace's margin notes, newest first, as id/author/body/at", %{ws: ws, root: root} do
    {:ok, a} = Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "cut 650fa4a", kind: "margin"})
    {:ok, b} = Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "#174 back to build", kind: "margin"})

    assert [%{id: bid, author: "uqbar", body: "#174 back to build", at: at}, %{id: aid}] = Margin.notes(ws.id)
    assert {bid, aid} == {b.id, a.id}
    assert is_integer(at)
  end

  test "only margin kind, only the root thread, capped", %{ws: ws, root: root, other: other} do
    {:ok, _} = Server.Channel.post(%{thread_id: root.id, author: "tlon", body: "chat", kind: "chat"})
    {:ok, _} = Server.Channel.post(%{thread_id: other.id, author: "uqbar", body: "elsewhere", kind: "margin"})
    for i <- 1..15, do: Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "n#{i}", kind: "margin"})

    notes = Margin.notes(ws.id)
    assert length(notes) == 12
    assert hd(notes).body == "n15"
    refute Enum.any?(notes, &(&1.body in ["chat", "elsewhere"]))
  end

  test "a workspace with no root thread has no margins" do
    assert Margin.notes(-1) == []
  end
end
