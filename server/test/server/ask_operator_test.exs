defmodule Server.AskOperatorTest do
  # A worker's question for the operator parks its thread on them (`awaiting`), the field every
  # "waiting on you" surface already reads; the operator's reply on a plain thread clears it. A
  # workline's gate is not a question: a reply leaves it parked until it is approved.
  use ExUnit.Case, async: false

  alias Server.Attention
  alias Server.Channel
  alias Server.Repo
  alias Server.Thread

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Asks"})
    {:ok, thread} = Channel.open_thread(%{title: "inbox design", scope: "machine", workspace_id: ws.id})
    %{thread: thread}
  end

  test "ask posts the question as the worker and parks the thread on the operator", %{thread: t} do
    assert {:ok, %{author: "hronir", body: "A or B?"}} = Attention.ask(t.id, "hronir", "A or B?")
    assert %Thread{awaiting: "andrew"} = Repo.get(Thread, t.id)
  end

  test "the operator's reply on a plain thread clears it", %{thread: t} do
    {:ok, _} = Attention.ask(t.id, "hronir", "A or B?")
    assert {:ok, _} = Attention.respond(t.id, "andrew", "A")
    assert %Thread{awaiting: nil} = Repo.get(Thread, t.id)
  end

  test "a workline's gate stays parked through a reply", %{thread: t} do
    {:ok, gated} = t |> Ecto.Changeset.change(stage: "spec", awaiting: "andrew") |> Repo.update()
    assert {:ok, _} = Attention.respond(gated.id, "andrew", "looks fine")
    assert %Thread{awaiting: "andrew"} = Repo.get(Thread, gated.id)
  end
end
