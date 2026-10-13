defmodule Server.SheriffTest do
  # The coworker who owns red: every red signal lands on the sheriff's beat (one standing thread per
  # workspace, the sheriff its lead), and a red verify leaves the operator's list for it.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Sheriff
  alias Server.Workspaces

  defmodule Conflicts do
    @moduledoc false
    def merge(_repo, _slug, _opts), do: {:error, "a conflict in wide.ts"}
  end

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Watched"})
    %{ws: ws}
  end

  defp beats(ws), do: Repo.all(from t in Server.Thread, where: t.workspace_id == ^ws.id and t.title == "sheriff's beat")

  defp reports(beat),
    do: Repo.all(from m in Message, where: m.thread_id == ^beat.id and like(m.body, "🚨%"), order_by: m.id)

  test "no sheriff on the bench: nothing is opened, the report says so", %{ws: ws} do
    {:ok, t} = Channel.open_thread(%{title: "red thing", workspace_id: ws.id})
    assert :no_sheriff = Sheriff.report(t, "verify is red")
    assert beats(ws) == []
  end

  test "a sheriff's reports land on one beat it leads, each naming the thread and what broke", %{ws: ws} do
    {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    {:ok, a} = Channel.open_thread(%{title: "argos", workspace_id: ws.id})
    {:ok, b} = Channel.open_thread(%{title: "stereo", workspace_id: ws.id})

    :ok = Sheriff.report(a, "verify is red: mise run check (exit 1)")
    :ok = Sheriff.report(b, "the merge queue bounced it back to build: a conflict")

    assert [beat] = beats(ws)
    assert Channel.thread_lead(beat.id) == "scharlach"
    assert [one, two] = reports(beat)
    assert one.body =~ "##{a.id} argos" and one.body =~ "verify is red"
    assert two.body =~ "##{b.id} stereo" and two.body =~ "bounced"
  end

  test "a landing the merge queue bounces is reported to the sheriff", %{ws: ws} do
    {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    {:ok, t} = Server.Workline.open(%{title: "w", slug: "conflicted", stage: "review", workspace_id: ws.id})
    {:ok, queued} = t |> Server.Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    assert {:error, {:bounced, _}} =
             Server.Workline.land_queued(queued, merge: Conflicts, gate: fn _, _ -> {:ok, :green} end)

    assert [beat] = beats(ws)
    assert [r] = reports(beat)
    assert r.body =~ "##{t.id}" and r.body =~ "a conflict in wide.ts"
  end

  describe "postmortems — a resolved incident is banked as a fact" do
    setup %{ws: ws} do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      {:ok, red} = Channel.open_thread(%{title: "argos", workspace_id: ws.id})
      :ok = Sheriff.report(red, "verify is red: mise run check (exit 1)")
      [beat] = beats(ws)
      %{beat: beat}
    end

    defp facts(thread_id), do: Repo.all(from f in Server.Fact, where: f.thread_id == ^thread_id)

    defp incident(thread_id),
      do: Server.Dossier.raise_issue(%{thread_id: thread_id, summary: "the clock test read the wall clock"})

    test "an incident resolved with its PR yields one fact with the PR linked", %{beat: beat} do
      {:ok, issue} = incident(beat.id)
      {:ok, _} = Server.Dossier.resolve_issue(issue, "froze the clock in the test, #123")

      assert [fact] = facts(beat.id)
      assert fact.text == "postmortem: the clock test read the wall clock — froze the clock in the test, #123"
      assert fact.kind == "learned" and fact.provenance == "derived"

      {:ok, _} = Server.Dossier.resolve_issue(Repo.get!(Server.Issue, issue.id), "again, #123")
      assert [_] = facts(beat.id)
    end

    test "a PR URL links it too", %{beat: beat} do
      {:ok, issue} = incident(beat.id)
      {:ok, _} = Server.Dossier.resolve_issue(issue, "https://github.com/o/r/pull/77")
      assert [fact] = facts(beat.id)
      assert fact.text =~ "/pull/77"
    end

    test "no PR named, or an issue off the beat: no postmortem", %{beat: beat, ws: ws} do
      {:ok, issue} = incident(beat.id)
      {:ok, _} = Server.Dossier.resolve_issue(issue, "went away on its own")
      assert facts(beat.id) == []

      {:ok, elsewhere} = Channel.open_thread(%{title: "elsewhere", workspace_id: ws.id})
      {:ok, other} = incident(elsewhere.id)
      {:ok, _} = Server.Dossier.resolve_issue(other, "fixed in #9")
      assert facts(elsewhere.id) == []
    end
  end

  test "an issue that can't be routed leaves no ticket behind to be filed twice", %{ws: ws} do
    {:ok, beat} = Channel.open_thread(%{title: "beat", workspace_id: ws.id})
    {:ok, issue} = Server.Dossier.raise_issue(%{thread_id: beat.id, summary: "nowhere to send this"})

    assert {:error, _} = Server.Dossier.fix_issue(issue)
    assert Server.Tickets.in_workspace(ws.id) == []
    assert %{ticket_id: nil} = Repo.get!(Server.Issue, issue.id)
  end

  describe "getting an issue fixed — a ticket owns it, its landing resolves it" do
    setup %{ws: ws} do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius-f", archetype: "surveyor"})
      {:ok, _} = Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
      {:ok, red} = Channel.open_thread(%{title: "argos", workspace_id: ws.id})
      :ok = Sheriff.report(red, "landing bounced: untracked server/tmp would be overwritten")
      [beat] = beats(ws)

      {:ok, issue} =
        Server.Dossier.raise_issue(%{
          thread_id: beat.id,
          summary: "landing rebase fails on test scratch",
          evidence: "82588e3 tracked server/tmp",
          found_by: "scharlach"
        })

      %{beat: beat, issue: issue}
    end

    test "the operator's 'get it fixed' files a ticket from the issue, routes it, and says who has it", %{
      ws: ws,
      beat: beat,
      issue: issue
    } do
      assert [%{kind: "issue"}] = Server.Office.Needs.list()

      assert {:ok, %{ticket: ticket, owner: "routed to tertius-f"}} = Server.Dossier.fix_issue(issue)
      assert ticket.workspace_id == ws.id and ticket.title == "landing rebase fails on test scratch"
      assert ticket.body =~ "82588e3 tracked server/tmp" and ticket.body =~ "issue ##{issue.id}"
      assert %{status: "todo"} = Server.Tickets.get(ticket.id)
      assert %{ticket_id: tid} = Repo.get!(Server.Issue, issue.id)
      assert tid == ticket.id

      assert Server.Office.Needs.list() == []

      assert [%{thread_id: thread_id, body: body}] = Server.Dossier.fixing_since(DateTime.add(DateTime.utc_now(), -60))
      assert thread_id == beat.id
      assert body =~ "issue ##{issue.id}" and body =~ "ticket ##{ticket.id}" and body =~ "routed to tertius-f"
    end

    test "an issue already owned or closed is not filed twice", %{issue: issue} do
      {:ok, _} = Server.Dossier.fix_issue(issue)
      assert {:error, :owned} = Server.Dossier.fix_issue(Repo.get!(Server.Issue, issue.id))

      {:ok, closed} = Server.Dossier.raise_issue(%{summary: "gone"})
      {:ok, closed} = Server.Dossier.resolve_issue(closed, "went away")
      assert {:error, :closed} = Server.Dossier.fix_issue(closed)
    end

    test "a coworker's ticket for the issue owns it too, named as theirs", %{ws: ws, issue: issue} do
      {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "clean server/tmp before the rebase"})
      {:ok, _} = Server.Dossier.own_issue(issue, ticket, "filed by scharlach")

      assert Server.Office.Needs.list() == []
      assert [%{body: body}] = Server.Dossier.fixing_since(DateTime.add(DateTime.utc_now(), -60))
      assert body =~ "filed by scharlach"
    end

    test "a ticket that ends without landing gives the issue back to the operator's list", %{ws: ws, issue: issue} do
      {:ok, %{ticket: ticket}} = Server.Dossier.fix_issue(issue)
      {:ok, work} = Channel.open_thread(%{title: "landing clears server/tmp", workspace_id: ws.id})
      {:ok, _} = Server.Tickets.promote(Server.Tickets.get(ticket.id), work.id)
      assert Server.Office.Needs.list() == []

      {:ok, _} = Channel.close_thread(work)

      assert %{status: "done"} = Server.Tickets.get(ticket.id)
      assert %{state: "open"} = Repo.get!(Server.Issue, issue.id)
      assert [%{kind: "issue", ref: ref}] = Server.Office.Needs.list()
      assert ref == issue.id
    end

    test "its workline landing resolves the issue naming the PR, which banks the postmortem", %{
      ws: ws,
      beat: beat,
      issue: issue
    } do
      {:ok, %{ticket: ticket}} = Server.Dossier.fix_issue(issue)
      {:ok, work} = Channel.open_thread(%{title: "landing clears server/tmp", workspace_id: ws.id})
      {:ok, _} = Server.Tickets.promote(Server.Tickets.get(ticket.id), work.id)

      assert [_] = Server.Dossier.resolve_fixed(work, "https://github.com/o/r/pull/330")

      assert %{state: "closed", resolution: "fixed by https://github.com/o/r/pull/330"} =
               Repo.get!(Server.Issue, issue.id)

      assert [%{text: "postmortem: landing rebase fails on test scratch — fixed by https://github.com/o/r/pull/330"}] =
               Repo.all(from f in Server.Fact, where: f.thread_id == ^beat.id)

      assert Server.Dossier.resolve_fixed(work, "https://github.com/o/r/pull/330") == []
    end
  end
end
