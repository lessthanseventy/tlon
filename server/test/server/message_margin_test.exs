defmodule Server.MessageMarginTest do
  use ExUnit.Case, async: false

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Margins"})
    {:ok, root} = Server.Channel.open_thread(%{title: "standing", scope: "machine", workspace_id: ws.id})
    %{root: root}
  end

  test "a margin note is a valid kind and survives the CHECK constraint", %{root: root} do
    assert {:ok, %Server.Message{kind: "margin"} = m} =
             Server.Channel.post(%{thread_id: root.id, author: "uqbar", body: "#174 back to build", kind: "margin"})

    assert %Server.Message{kind: "margin"} = Server.Repo.get(Server.Message, m.id)
  end

  test "an unknown kind is still refused" do
    cs = Server.Message.post_changeset(%{thread_id: 1, author: "a", body: "b", kind: "scribble"})
    refute cs.valid?
  end
end
