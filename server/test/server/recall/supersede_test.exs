defmodule Server.Recall.SupersedeTest do
  # A newly embedded fact supersedes the older live fact in its scope that says the same thing.
  # Offline: vectors are injected through store_embedding/3, the seam embed_fact/1 writes through.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Fact
  alias Server.Recall
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "dedupe"})
    {:ok, tlon} = Server.Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})
    {:ok, other} = Server.Projects.register(%{workspace_id: ws.id, name: "other", repos: []})
    {:ok, a} = Channel.open_thread(%{title: "a", workspace_id: ws.id, project_id: tlon.id})
    {:ok, b} = Channel.open_thread(%{title: "b", workspace_id: ws.id, project_id: tlon.id})
    {:ok, elsewhere} = Channel.open_thread(%{title: "c", workspace_id: ws.id, project_id: other.id})
    %{a: a, b: b, elsewhere: elsewhere}
  end

  defp bank(thread, text, vector, provenance \\ "derived") do
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: provenance})
    {:ok, fact} = Recall.store_embedding(fact, vector, "test")
    fact
  end

  defp supersedes(fact), do: Repo.get(Fact, fact.id).supersedes

  test "an exact duplicate (case and whitespace aside) supersedes the older fact, whatever its vector", %{a: a, b: b} do
    old = bank(a, "Menard edits Elixir.", [1.0, 0.0])
    new = bank(b, "  menard   edits elixir. ", [0.0, 1.0])
    assert supersedes(new) == old.id
  end

  test "a near-identical embedding supersedes the older fact in the same project", %{a: a, b: b} do
    old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "release smoke runs on port 4047", [0.99, 0.05])
    assert supersedes(new) == old.id
  end

  test "an unrelated fact supersedes nothing", %{a: a, b: b} do
    _old = bank(a, "the smoke port is 4047", [1.0, 0.0])
    new = bank(b, "golden hashes live in golden.json", [0.6, 0.8])
    assert is_nil(supersedes(new))
  end

  test "another project's duplicate is out of scope", %{a: a, elsewhere: elsewhere} do
    _old = bank(a, "menard edits elixir", [1.0, 0.0])
    new = bank(elsewhere, "menard edits elixir", [1.0, 0.0])
    assert is_nil(supersedes(new))
  end

  test "a derived fact never supersedes a stated one", %{a: a, b: b} do
    _stated = bank(a, "always use mise", [1.0, 0.0], "stated")
    new = bank(b, "always use mise", [1.0, 0.0])
    assert is_nil(supersedes(new))
  end

  test "a chain supersedes the newest live duplicate, not one already superseded", %{a: a, b: b} do
    first = bank(a, "menard edits elixir", [1.0, 0.0])
    second = bank(b, "menard edits elixir", [1.0, 0.0])
    third = bank(a, "menard edits elixir", [1.0, 0.0])
    assert supersedes(second) == first.id
    assert supersedes(third) == second.id
  end

  test "backfill reports the chain it would write and writes only when told", %{a: a, b: b} do
    insert = fn thread, text ->
      {:ok, f} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: "derived"})
      f
    end

    first = insert.(a, "menard edits elixir")
    second = insert.(b, "Menard edits Elixir")
    third = insert.(a, "menard edits elixir")
    _other = insert.(b, "something else")

    expected = [{second.id, first.id, :exact}, {third.id, second.id, :exact}]
    assert Server.Recall.Supersede.backfill() == expected
    assert is_nil(supersedes(second))

    assert Server.Recall.Supersede.backfill(write: true) == expected
    assert supersedes(third) == second.id
    assert Server.Recall.Supersede.backfill() == []
  end

  test "the superseded fact is demoted in the working set", %{a: a, b: b} do
    old = bank(a, "menard edits elixir", [1.0, 0.0])
    new = bank(b, "menard edits elixir", [1.0, 0.0])
    ws = Recall.working_set_for_thread(a, budget: 10_000)
    strength = Map.new(ws, &{&1.id, &1.strength})
    assert Map.get(strength, old.id, 0) < strength[new.id]
  end
end
