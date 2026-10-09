defmodule Server.Recall.JudgeTest do
  # A fact related to an older one (cosine in the judge's band, below Supersede's duplicate line) is
  # judged by the cheap model: new, restates or corrects. Offline: vectors are written straight to the
  # row and the model is a function handed in.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Recall.Judge
  alias Server.Recall.Supersede
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "judge"})
    {:ok, tlon} = Server.Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})
    {:ok, a} = Channel.open_thread(%{title: "a", workspace_id: ws.id, project_id: tlon.id})
    {:ok, b} = Channel.open_thread(%{title: "b", workspace_id: ws.id, project_id: tlon.id})
    %{a: a, b: b}
  end

  defp bank(thread, text, vector, provenance \\ "derived") do
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: provenance})
    fact |> Fact.embedding_changeset(vector, "test") |> Repo.update!()
  end

  defp says(json), do: fn _prompt -> {:ok, json} end
  defp verdict(v, id, reason), do: says(~s({"verdict": "#{v}", "id": #{id}, "reason": "#{reason}"}))
  defp flag_on, do: {:ok, true} = FunWithFlags.enable(:judged_supersede)
  defp supersedes(fact), do: Repo.get(Fact, fact.id).supersedes
  defp events(kind), do: Repo.all(from(e in Event, where: e.kind == ^kind))

  # cosine([1, 0], [0.85, 0.53]) ≈ 0.85: related, not a duplicate
  @related [0.85, 0.53]

  test "flag off: a correction is only proposed, with its reason, and nothing is superseded", %{a: a, b: b} do
    old = bank(a, "in_flight counts every todo ticket", [1.0, 0.0])
    new = bank(b, "in_flight skips a todo ticket whose thread is closed", @related)

    Judge.judge(new, model: verdict("corrects", old.id, "the fix changed what in_flight counts"))

    assert is_nil(supersedes(new))
    assert [event] = events("supersede_proposed")
    assert event.correlation == "fact:#{new.id}"
    assert event.thread_id == b.id

    assert event.detail == %{
             "old" => old.id,
             "verdict" => "corrects",
             "reason" => "the fix changed what in_flight counts",
             "how" => "judged"
           }
  end

  test "flag on: a restatement supersedes, recorded as superseded with its reason", %{a: a, b: b} do
    flag_on()
    old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "release smoke listens on 4047", @related)

    judged = Judge.judge(new, model: verdict("restates", old.id, "same port"))

    assert judged.supersedes == old.id
    assert supersedes(new) == old.id
    assert [%{detail: %{"old" => old_id, "verdict" => "restates", "reason" => "same port"}}] = events("superseded")
    assert old_id == old.id
    assert events("supersede_proposed") == []
  end

  test "a 'new' verdict, an id the model invented, or a reply that doesn't parse changes nothing", %{a: a, b: b} do
    flag_on()
    old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "release smoke listens on 4047", @related)

    for model <- [verdict("new", 0, "different"), verdict("corrects", old.id + 999, "x"), says("no json here")] do
      Judge.judge(new, model: model)
    end

    assert is_nil(supersedes(new))
    assert Repo.aggregate(Event, :count) == 0
  end

  test "only the related band is judged: a duplicate is Supersede's, an unrelated fact nobody's", %{a: a, b: b} do
    _dup = bank(a, "menard edits elixir", [1.0, 0.0])
    _far = bank(a, "golden hashes live in golden.json", [0.0, 1.0])
    new = bank(b, "menard edits elixir files", [0.999, 0.01])

    Judge.judge(new, model: fn _ -> flunk("no neighbour in the band, no model call") end)
  end

  test "the model down: nothing happens", %{a: a, b: b} do
    flag_on()
    _old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "release smoke listens on 4047", @related)

    assert %Fact{supersedes: nil} = Judge.judge(new, model: fn _ -> {:error, {:model_cli_timeout, 20}} end)
    assert Repo.aggregate(Event, :count) == 0
  end

  test "a stated fact is never superseded: a restatement of it does nothing", %{a: a, b: b} do
    flag_on()
    stated = bank(a, "always use mise", [1.0, 0.0], "stated")
    new = bank(b, "drive everything through mise tasks", @related)

    Judge.judge(new, model: verdict("restates", stated.id, "same rule"))

    assert is_nil(supersedes(new))
    assert Repo.aggregate(Event, :count) == 0
  end

  test "a derived fact contradicting a stated one is asked of the operator, not superseded", %{a: a, b: b} do
    flag_on()
    stated = bank(a, "always use mise", [1.0, 0.0], "stated")
    new = bank(b, "mise is no longer used, run mix directly", @related)

    Judge.judge(new, model: verdict("corrects", stated.id, "says mise is gone"))

    assert is_nil(supersedes(new))
    assert is_nil(supersedes(stated))
    assert [ask] = Server.Attention.open_asks()
    assert ask.thread_id == b.id
    assert ask.body =~ "##{stated.id}"
    assert ask.body =~ "says mise is gone"
  end

  test "flag off, the same contradiction is only proposed — no ask", %{a: a, b: b} do
    stated = bank(a, "always use mise", [1.0, 0.0], "stated")
    new = bank(b, "mise is no longer used, run mix directly", @related)

    Judge.judge(new, model: verdict("corrects", stated.id, "says mise is gone"))

    assert Server.Attention.open_asks() == []
    assert [_] = events("supersede_proposed")
  end

  test "apply_proposal does what the flag would have; it applies once", %{a: a, b: b} do
    old = bank(a, "in_flight counts every todo ticket", [1.0, 0.0])
    new = bank(b, "in_flight skips a todo ticket whose thread is closed", @related)
    Judge.judge(new, model: verdict("corrects", old.id, "the fix"))
    [proposal] = events("supersede_proposed")

    assert {:ok, %Fact{supersedes: old_id}} = Supersede.apply_proposal(proposal.id)
    assert old_id == old.id
    assert [%{detail: %{"proposal" => pid, "reason" => "the fix"}}] = events("superseded")
    assert pid == proposal.id
    assert {:error, :resolved} = Supersede.apply_proposal(proposal.id)
    assert {:error, :resolved} = Supersede.reject_proposal(proposal.id, "too late")
  end

  test "reject_proposal records why and supersedes nothing", %{a: a, b: b} do
    old = bank(a, "in_flight counts every todo ticket", [1.0, 0.0])
    new = bank(b, "in_flight skips a todo ticket whose thread is closed", @related)
    Judge.judge(new, model: verdict("corrects", old.id, "the fix"))
    [proposal] = events("supersede_proposed")

    assert {:ok, %Event{kind: "supersede_rejected", detail: detail}} =
             Supersede.reject_proposal(proposal.id, "they describe before and after, both true")

    assert detail["rejected"] == "they describe before and after, both true"
    assert detail["proposal"] == proposal.id
    assert is_nil(supersedes(new))
    assert {:error, :resolved} = Supersede.apply_proposal(proposal.id)
    assert {:error, :not_found} = Supersede.apply_proposal(-1)
  end

  test "the prompt names each neighbour by id", %{a: a, b: b} do
    old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "release smoke listens on 4047", @related)

    model = fn prompt ->
      send(self(), {:prompt, prompt})
      {:ok, "{}"}
    end

    Judge.judge(new, model: model)

    assert_received {:prompt, prompt}
    assert prompt =~ "##{old.id}"
    assert prompt =~ "release smoke listens on 4047"
  end
end
