defmodule Server.Maintain.StaleFlakesTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Maintain.Sweep
  alias Server.Repo
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Flakes"})
    %{ws: ws}
  end

  defp aged(ticket, days) do
    at = DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)
    {1, _} = Repo.update_all(from(t in Server.Ticket, where: t.id == ^ticket.id), set: [updated_at: at, created_at: at])
    ticket
  end

  test "a flake seen once and left alone for a week closes, its issue with it; anything else stays", %{ws: ws} do
    {:ok, old} = Tickets.file(%{workspace_id: ws.id, title: "Flake: hall-hire test empty pane"})
    {:ok, issue} = Server.Dossier.raise_issue(%{summary: "hall-hire flaked"})
    {:ok, _} = Server.Dossier.own_issue(issue, old, "test")
    aged(old, 8)

    {:ok, labelled} =
      Tickets.file(%{workspace_id: ws.id, title: "canvas paint test races git gc", labels: ["flaky", "tests"]})

    aged(labelled, 9)
    {:ok, fresh} = Tickets.file(%{workspace_id: ws.id, title: "Flake: a new one"})
    {:ok, recurring} = Tickets.file(%{workspace_id: ws.id, title: "Flake: keeps biting"})
    {:ok, _} = Tickets.update(recurring, %{seen: 3})
    aged(recurring, 10)
    {:ok, started} = Tickets.file(%{workspace_id: ws.id, title: "Flake: someone is on it"})
    {:ok, _} = Tickets.update(started, %{status: "doing"})
    aged(started, 10)
    {:ok, real} = Tickets.file(%{workspace_id: ws.id, title: "the pool table plays itself"})
    aged(real, 30)

    closed = Sweep.sweep_stale_flakes() |> Enum.map(& &1.id) |> Enum.sort()

    assert closed == Enum.sort([old.id, labelled.id])
    assert Tickets.get(old.id).body =~ "Closed by the sweep: a flake not seen again in 7 days"
    assert Repo.get(Server.Issue, issue.id).state == "closed"
    for t <- [fresh, recurring, started, real], do: refute(Tickets.get(t.id).status == "done")
  end
end
