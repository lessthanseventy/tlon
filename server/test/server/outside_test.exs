defmodule Server.OutsideTest do
  # Uqbar design §6: the operator's own Claude Code session is a citizen — its posts signed as itself,
  # never as the operator — but not a seat: no desk, no staffing, no intake. And the door it posts
  # through can't be used to speak as a coworker on a bench.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Outside

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "the lobby"})
    %{thread: thread}
  end

  test "posts signed by the outside citizen, not the operator", %{thread: thread} do
    {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
    assert {:ok, %{author: "uqbar"}} = Outside.post(thread.id, "uqbar", "a margin note")
    assert %{author: "uqbar", body: "a margin note"} = List.last(Channel.thread_messages(thread))
  end

  test "refuses a name that is a seated coworker, or no agent at all", %{thread: thread} do
    {:ok, ws} = Server.Workspaces.create(%{name: "Bench"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "tertius-o", archetype: "surveyor"})

    assert {:error, :seated} = Outside.post(thread.id, "tertius-o", "speaking for tertius")
    assert {:error, :no_such_citizen} = Outside.post(thread.id, "nobody", "hello")
    assert Channel.thread_messages(thread) == []
  end
end
