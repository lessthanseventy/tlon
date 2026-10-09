defmodule Server.LibrarianTest do
  # The steward of the office's memory: it retires and forgets facts with a reason it leaves on the
  # record, decides the correction judge's proposals, and never demotes what the operator stated.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Librarian
  alias Server.Message
  alias Server.Repo
  alias Server.Workspaces

  defmodule Judge do
    @moduledoc false
    def apply_proposal(id) do
      send(self(), {:applied, id})
      {:ok, :applied}
    end

    def reject_proposal(id, reason) do
      send(self(), {:rejected, id, reason})
      {:ok, :rejected}
    end
  end

  defmodule NoJudge do
    @moduledoc false
  end

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Stacks"})
    :ok = Server.Bootstrap.ensure_standing(ws)
    {:ok, t} = Channel.open_thread(%{title: "the catalogue", workspace_id: ws.id})
    on_exit(fn -> Application.delete_env(:server, :supersede_judge) end)
    %{ws: ws, t: t}
  end

  defp fact!(t, text, provenance \\ "derived") do
    {:ok, f} = Dossier.bank_fact(%{thread_id: t.id, kind: "learned", provenance: provenance, text: text})
    f
  end

  defp events(kind), do: Repo.all(from e in Event, where: e.kind == ^kind, order_by: e.id)

  defp propose!(t, new, old) do
    {:ok, e} =
      Dossier.record_event(%{
        thread_id: t.id,
        kind: "supersede_proposed",
        correlation: "fact:#{new.id}",
        detail: %{"old" => old.id, "verdict" => "supersedes", "reason" => "the port moved", "how" => "judge"}
      })

    e
  end

  describe "supersede/4" do
    test "points the newer fact at the older one and records why", %{t: t} do
      old = fact!(t, "the service listens on 4040")
      new = fact!(t, "the service listens on 4041")

      assert {:ok, %Fact{supersedes: id}} = Librarian.supersede(old.id, new.id, "the port moved", by: "quain")
      assert id == old.id

      assert [%Event{correlation: corr, detail: detail}] = events("superseded")
      assert corr == "fact:#{new.id}"
      assert detail["old"] == old.id and detail["reason"] == "the port moved" and detail["by"] == "quain"
    end

    test "refuses to retire a stated fact, and writes nothing", %{t: t} do
      stated = fact!(t, "never push to main", "stated")
      new = fact!(t, "pushing to main is fine now")

      assert {:error, :stated} = Librarian.supersede(stated.id, new.id, "outdated", by: "quain")
      assert Repo.get!(Fact, new.id).supersedes == nil
      assert events("superseded") == []
    end

    test "refuses without a reason, a fact onto itself, and a fact it cannot find", %{t: t} do
      a = fact!(t, "a")
      b = fact!(t, "b")
      assert {:error, :no_reason} = Librarian.supersede(a.id, b.id, "  ", by: "quain")
      assert {:error, :same_fact} = Librarian.supersede(a.id, a.id, "dup", by: "quain")
      assert {:error, :not_found} = Librarian.supersede(a.id, -1, "dup", by: "quain")
    end

    test "a fact outside the caller's workspace is not found", %{t: t} do
      {:ok, other} = Workspaces.register(%{name: "Elsewhere"})
      a = fact!(t, "a")
      b = fact!(t, "b")
      assert {:error, :not_found} = Librarian.supersede(a.id, b.id, "dup", by: "quain", workspace_id: other.id)
    end
  end

  describe "forget/3" do
    test "tombstones junk with its reason on the record", %{t: t} do
      junk = fact!(t, "...")
      assert {:ok, %Fact{forgotten_at: %DateTime{}}} = Librarian.forget(junk.id, "placeholder text", by: "quain")
      assert [%Event{correlation: corr, detail: %{"reason" => "placeholder text"}}] = events("forgotten")
      assert corr == "fact:#{junk.id}"
    end

    test "never forgets a stated fact", %{t: t} do
      stated = fact!(t, "the operator said so", "stated")
      assert {:error, :stated} = Librarian.forget(stated.id, "stale", by: "quain")
      assert Repo.get!(Fact, stated.id).forgotten_at == nil
    end
  end

  describe "proposals/1 and decide/4" do
    test "lists open proposals with both facts' text; a decided or done one drops out", %{ws: ws, t: t} do
      old = fact!(t, "deploys run from main")
      new = fact!(t, "deploys run from the live pointer")
      e = propose!(t, new, old)

      assert [p] = Librarian.proposals(ws.id)
      assert p.event_id == e.id
      assert p.new.text == "deploys run from the live pointer" and p.old.text == "deploys run from main"
      assert p.verdict == "supersedes" and p.reason == "the port moved"

      {:ok, _} = Librarian.supersede(old.id, new.id, "agreed with the judge", by: "quain")
      assert Librarian.proposals(ws.id) == []
    end

    test "a citation of the new fact does not close its proposal", %{ws: ws, t: t} do
      old = fact!(t, "x is 1")
      new = fact!(t, "x is 2")
      propose!(t, new, old)
      Dossier.cite_facts([new.id], t.id, %{"via" => "search_facts"})
      assert [_] = Librarian.proposals(ws.id)
    end

    test "without the judge installed, deciding says so and changes nothing", %{t: t} do
      Application.put_env(:server, :supersede_judge, NoJudge)
      old = fact!(t, "x is 1")
      new = fact!(t, "x is 2")
      e = propose!(t, new, old)

      assert {:error, :judge_not_installed} = Librarian.decide(e.id, "apply", "right", by: "quain")
      assert {:error, :judge_not_installed} = Librarian.decide(e.id, "reject", "wrong", by: "quain")
      assert Repo.get!(Fact, new.id).supersedes == nil
    end

    test "with the judge installed, apply and reject go through it", %{t: t} do
      Application.put_env(:server, :supersede_judge, Judge)
      old = fact!(t, "x is 1")
      new = fact!(t, "x is 2")
      e = propose!(t, new, old)

      assert {:ok, :applied} = Librarian.decide(e.id, "apply", "right", by: "quain")
      assert_received {:applied, id} when id == e.id
      assert {:ok, :rejected} = Librarian.decide(e.id, "reject", "different claims", by: "quain")
      assert_received {:rejected, id, "different claims"} when id == e.id
    end

    test "refuses to apply over a stated fact, a non-proposal, and a reject with no reason", %{t: t} do
      Application.put_env(:server, :supersede_judge, Judge)
      stated = fact!(t, "the operator's rule", "stated")
      new = fact!(t, "our paraphrase")
      e = propose!(t, new, stated)
      {:ok, cited} = Dossier.record_event(%{thread_id: t.id, kind: "cited", correlation: "fact:#{new.id}"})

      assert {:error, :stated} = Librarian.decide(e.id, "apply", "", by: "quain")
      assert {:error, :not_a_proposal} = Librarian.decide(cited.id, "apply", "", by: "quain")
      assert {:error, :no_reason} = Librarian.decide(e.id, "reject", "", by: "quain")
      assert {:error, :bad_decision} = Librarian.decide(e.id, "maybe", "hmm", by: "quain")
      refute_received {:applied, _}
    end
  end

  describe "report/3" do
    test "posts the counts and the librarian's notes in the lobby, waking no one", %{ws: ws, t: t} do
      fact!(t, "a stated rule", "stated")
      fact!(t, "a finding")
      junk = fact!(t, "...")
      {:ok, _} = Librarian.forget(junk.id, "placeholder", by: "quain")

      assert {:ok, %Message{} = m} = Librarian.report(ws.id, "the port facts are shaky", by: "quain")
      assert m.thread_id == Channel.machine_thread(ws.id).id
      assert m.author == "quain" and m.delivered_at
      assert m.body =~ "2 live facts (1 stated, 1 derived)"
      assert m.body =~ "1 forgotten"
      assert m.body =~ "the port facts are shaky"
    end

    test "refuses notes that @mention the operator", %{ws: ws} do
      assert {:error, :mentions_operator} = Librarian.report(ws.id, "@andrew please look", by: "quain")
    end
  end

  describe "ensure_schedules/2" do
    test "a daily sweep and a weekly report for the seat, once", %{ws: ws} do
      [sweep, weekly] = Librarian.ensure_schedules(ws.id, "quain")
      assert sweep.cron == "0 7 * * *" and sweep.agent == "quain" and sweep.standing and sweep.kind == "agent"
      assert sweep.body =~ "review_proposals"
      assert weekly.cron == "30 7 * * 1" and weekly.body =~ "knowledge_report"

      Librarian.ensure_schedules(ws.id, "quain")
      assert length(Server.Schedules.in_workspace(ws.id)) == 2
    end
  end

  test "of/1 finds the bench's librarian", %{ws: ws} do
    assert Librarian.of(ws.id) == nil
    {:ok, _} = Workspaces.seat(ws.id, %{name: "quain", archetype: "librarian", grade: "senior"})
    assert %{name: "quain"} = Librarian.of(ws.id)
  end
end
