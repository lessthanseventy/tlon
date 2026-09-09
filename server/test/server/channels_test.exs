defmodule Server.ChannelsTest do
  # Channels (UX slice 1b, 2026-09-08): the layer between a workspace and its threads, Slack's
  # exactly. Every workspace has `#general`; topic channels are created by name; a thread lives
  # in exactly one channel and can be moved. The old "root machine thread" is what #general
  # stood in for.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Channels
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Tlön"})
    %{ws: ws}
  end

  test "registering a workspace gives it #general; general/1 finds it", %{ws: ws} do
    assert %{name: "general", kind: "general", workspace_id: wid} = Channels.general(ws.id)
    assert wid == ws.id
    assert [%{name: "general"}] = Channels.in_workspace(ws.id)
  end

  test "a topic channel is created by name, unique per workspace, and listed after general", %{ws: ws} do
    assert {:ok, reviews} = Channels.create(ws.id, "reviews")
    assert reviews.kind == "topic"
    assert {:error, _changeset} = Channels.create(ws.id, "reviews")
    assert ["general", "reviews"] = ws.id |> Channels.in_workspace() |> Enum.map(& &1.name)
  end

  test "a thread opens in #general by default, or in the channel named", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "plain", workspace_id: ws.id})
    assert t.channel_id == Channels.general(ws.id).id

    {:ok, infra} = Channels.create(ws.id, "infra")
    {:ok, t2} = Channel.open_thread(%{title: "disk", workspace_id: ws.id, channel_id: infra.id})
    assert t2.channel_id == infra.id
  end

  test "move/2 puts a thread in another channel of the SAME workspace; another workspace's is refused", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "wander", workspace_id: ws.id})
    {:ok, infra} = Channels.create(ws.id, "infra")
    assert {:ok, moved} = Channels.move(t, infra.id)
    assert moved.channel_id == infra.id

    {:ok, other} = Workspaces.register(%{name: "Freedonia"})
    assert {:error, :other_workspace} = Channels.move(moved, Channels.general(other.id).id)
  end

  test "deleting a topic channel rehomes its threads in #general; #general itself is refused", %{ws: ws} do
    {:ok, infra} = Channels.create(ws.id, "infra")
    {:ok, t} = Channel.open_thread(%{title: "disk", workspace_id: ws.id, channel_id: infra.id})
    assert {:ok, _} = Channels.delete(infra)
    assert Channel.thread(t.id).channel_id == Channels.general(ws.id).id
    assert {:error, :general} = Channels.delete(Channels.general(ws.id))
  end
end
