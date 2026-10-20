defmodule Server.RecurrenceTest do
  use ExUnit.Case, async: false

  alias Server.Dossier
  alias Server.Recurrence
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Work"})
    {:ok, workspace: ws}
  end

  test "a title that shares the fault's words finds the open ticket; an unrelated one finds nothing", %{workspace: ws} do
    {:ok, t} =
      Tickets.file(%{workspace_id: ws.id, title: "hall-hire test flakes: tmux socket reused after kill-server"})

    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "the pool table plays itself"})

    assert [%{id: id}] = Recurrence.similar_tickets(ws.id, "Flake: hall-hire test, the tmux socket is reused")
    assert id == t.id
    assert [] = Recurrence.similar_tickets(ws.id, "a doom wad for the arcade")
  end

  test "a ticket closed within 30 days still matches, so a recurrence reopens it rather than refiling", %{workspace: ws} do
    {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "smoke holder pid collides with a live process"})
    {:ok, _} = Tickets.update(t, %{status: "done"})

    assert [%{id: id}] = Recurrence.similar_tickets(ws.id, "smoke holder pid is a live process")
    assert id == t.id
  end

  test "seen again: the count rises, the detail is appended, a closed ticket reopens, and at three it is high", %{
    workspace: ws
  } do
    {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "the wake alarm fires falsely", priority: "low"})
    {:ok, _} = Tickets.update(t, %{status: "done"})

    {:ok, again} = Recurrence.ticket_seen(t.id, "fired for nolan on #294", "scharlach")
    assert again.seen == 2 and again.status == "backlog" and again.priority == "low"
    assert again.body =~ "Seen again" and again.body =~ "fired for nolan on #294" and again.body =~ "scharlach"

    {:ok, third} = Recurrence.ticket_seen(t.id, "and again", "scharlach")
    assert third.seen == 3 and third.priority == "high"
  end

  test "the sheriff's own duplicate is caught: one false wake alarm, worded twice" do
    {:ok, first} =
      Dossier.raise_issue(%{
        summary:
          "A wake-not-taken alert fired at 13:12 for pierre on #300, which was already closed, even though " <>
            "pierre's session was answering. Why: tertius @mentioned pierre on #300 (#9707, #9711). pierre doesn't le"
      })

    second =
      "The wake-not-taken alarm fired for nolan on #294 at 17:12 while nolan was healthy. nolan is QA and not " <>
        "#294's lead, and their session is bound to the lobby (#1). Every @nolan wake queued on #294 sits"

    assert first.id in Enum.map(Recurrence.similar_issues(second), & &1.id)
  end

  test "an issue seen again reopens, counts, and its ticket counts too", %{workspace: ws} do
    {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "a false wake alarm"})
    {:ok, issue} = Dossier.raise_issue(%{summary: "The wake-not-taken alarm fired for pierre on #300"})
    {:ok, _} = Dossier.own_issue(issue, t, "test")
    {:ok, _} = Dossier.resolve_issue(Server.Repo.get(Server.Issue, issue.id), "fixed")

    assert [%{id: id}] = Recurrence.similar_issues("The wake-not-taken alarm fired for nolan on #294")
    assert id == issue.id

    {:ok, again} = Recurrence.issue_seen(issue.id, "fired for nolan on #294", "scharlach")
    assert again.seen == 2 and again.state == "open" and again.evidence =~ "nolan"
    assert Tickets.get(t.id).seen == 2
  end
end
