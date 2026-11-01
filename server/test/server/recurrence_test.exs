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

  describe "against the real ticket corpus (test/fixtures/recurrence_titles.tsv: every title on the board)" do
    setup %{workspace: ws} do
      rows =
        "test/fixtures/recurrence_titles.tsv"
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&String.split(&1, "\t", parts: 2))

      for [_, title] <- rows, do: {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: title})
      {:ok, by_fixture_id: Map.new(rows, fn [id, title] -> {String.to_integer(id), title} end)}
    end

    test "a re-worded sighting finds the ticket filed for the same fault (#711 over #712)", %{
      workspace: ws,
      by_fixture_id: titles
    } do
      found =
        Recurrence.similar_tickets(
          ws.id,
          "hand_to: a raising Profiles.model_label skips the leads brief, so the new lead is never woken"
        )

      assert titles[712] in Enum.map(found, & &1.title)
    end

    # each: a title the check refused in the wild, and the unrelated tickets it was refused over
    @refused [
      {"Publish.fetch_branch/3 is subsumed by prune_branch; merge_again fetches origin twice", [176]},
      {"Roster trust tie-break follow-ups", [290, 452]},
      {"hand_to: a raising Profiles.model_label skips the leads brief, so the new lead is never woken", [518]},
      {"Leftover Postgres databases are never dropped after a test run", [452, 140, 156]},
      {"smoke_test: the real rev-parse path is untested", [353, 329, 528]},
      {"smoke_test: the replace to TERM path is untested", [723, 525, 628]},
      {"adapters/claude-code: typecheck mod.ts against the host's API types in the gate", [201, 452, 445]},
      {"read dirs left out of the brief post 7 times", [514, 245, 318]},
      {"The adapter's own holds (push_branch, main-checkout switch) carry no PreToolUse: prefix, so Needs reads them as permission refusals and always rings the operator",
       [415, 668, 385]},
      {"adapters/claude-code README and citizen.ts name `tlon-cli code`, a subcommand that doesn't exist",
       [655, 301, 173]},
      {"workspace_repo/2 resolves a repo name shared by two projects", [451, 726, 627]},
      {"A blocked need re-raises after it is settled: nothing marks the settlement", [175, 643, 470]},
      {"Script tests post fake gate and smoke runs to the live service's /api/release/ran", [462, 767, 302]}
    ]

    for {{title, unrelated}, n} <- Enum.with_index(@refused) do
      test "refused title #{n} no longer matches the tickets it was refused over", %{
        workspace: ws,
        by_fixture_id: titles
      } do
        found = ws.id |> Recurrence.similar_tickets(unquote(title)) |> Enum.map(& &1.title)

        for id <- unquote(unrelated), do: refute(titles[id] in found, "matched ##{id}: #{titles[id]}")
      end
    end
  end
end
