defmodule Server.SeedTest do
  # Reset-safe base knowledge: Server.Seed banks the repo's self-knowledge facts + baseline projects
  # idempotently, keyed by fact `intent` and (workspace, name).
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Bootstrap
  alias Server.Fact
  alias Server.Projects
  alias Server.Repo
  alias Server.Seed

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "load/0 reads the seed file into facts + projects lists" do
    data = Seed.load()
    assert is_list(data.facts) and data.facts != []
    # Projects are no longer seeded (client efforts are separate workspaces, 2026-08-31) — just a list.
    assert is_list(data.projects)
    # Every fact carries the required shape + a stable intent key.
    assert Enum.all?(data.facts, &match?(%{intent: _, kind: _, text: _, provenance: _}, &1))
  end

  describe "fact promotion — learnings graduate into the wipe-proof seed" do
    setup do
      path = Path.join(System.tmp_dir!(), "promoted-#{System.unique_integer([:positive])}.exs")
      Application.put_env(:server, :promoted_facts_path, path)

      on_exit(fn ->
        Application.delete_env(:server, :promoted_facts_path)
        File.rm(path)
      end)

      %{path: path}
    end

    test "promote/3 appends a fact's seed-entry under an intent, idempotently" do
      fact = %Fact{kind: "learned", text: "the arbiter is Console.Arbiter", provenance: "stated"}

      one = Seed.promote(fact, [], "seed:promoted:arbiter")

      assert one == [
               %{
                 intent: "seed:promoted:arbiter",
                 kind: "learned",
                 provenance: "stated",
                 text: "the arbiter is Console.Arbiter"
               }
             ]

      # same intent again → no duplicate
      assert Seed.promote(fact, one, "seed:promoted:arbiter") == one
      # a promoted learning with no provenance is recorded as our derived claim
      assert [_, %{provenance: "derived"}] = Seed.promote(%Fact{kind: "learned", text: "x"}, one, "seed:promoted:x")
    end

    test "write_promoted/1 round-trips through the file, and load/0 merges it in" do
      curated = Seed.load().facts

      Seed.write_promoted([
        %{intent: "seed:promoted:demo", kind: "learned", provenance: "derived", text: "a promoted learning"}
      ])

      assert Seed.promoted_facts() == [
               %{intent: "seed:promoted:demo", kind: "learned", provenance: "derived", text: "a promoted learning"}
             ]

      merged = Seed.load().facts
      assert length(merged) == length(curated) + 1
      assert Enum.any?(merged, &(&1.intent == "seed:promoted:demo"))
    end

    test "promote_fact/2 resolves a banked fact by id and generates an intent when none is given" do
      {:ok, thread} = Server.Channel.open_thread(%{title: "t"})

      {:ok, fact} =
        Server.Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "a real learning", provenance: "derived"})

      assert {:ok, intent, 1} = Seed.promote_fact(fact.id)
      assert intent == "seed:promoted:#{fact.id}"
      assert [%{text: "a real learning"}] = Seed.promoted_facts()

      # an explicit intent is honored, and re-promoting the same intent is idempotent
      assert {:ok, "seed:custom", 2} = Seed.promote_fact(fact.id, "seed:custom")
      assert {:ok, "seed:custom", 2} = Seed.promote_fact(fact.id, "seed:custom")

      assert {:error, :no_fact} = Seed.promote_fact(999_999)
    end

    test "ensure/0 banks a promoted fact (it survives a wipe like any seed fact)" do
      Seed.write_promoted([
        %{intent: "seed:promoted:survives", kind: "learned", provenance: "derived", text: "promoted knowledge"}
      ])

      Seed.ensure()

      assert Repo.exists?(from f in Fact, where: f.intent == "seed:promoted:survives")
    end
  end

  test "ensure/0 banks the base facts and the baseline projects" do
    {:ok, workspace} = Bootstrap.ensure()
    # Bootstrap already seeded once; count what a from-empty apply banks by clearing first.
    Repo.delete_all(Fact)
    for p <- Projects.in_workspace(workspace.id), p.name != "general", do: Projects.remove(p)

    seed = Seed.load()
    %{facts: banked, projects: ensured} = Seed.ensure()

    assert banked == length(seed.facts)
    assert ensured == length(seed.projects)
    # The self-knowledge landed as always-loaded constraint/stated facts, findable by intent.
    assert Repo.exists?(from f in Fact, where: f.intent == "seed:tlon-what")
  end

  test "ensure/0 is idempotent — a second apply banks nothing new" do
    {:ok, _workspace} = Bootstrap.ensure()
    Seed.ensure()
    assert %{facts: 0, projects: 0} = Seed.ensure()
  end

  test "a manually-forgotten seed fact is NOT resurrected (existence-by-intent respects the tombstone)" do
    {:ok, _workspace} = Bootstrap.ensure()
    Seed.ensure()

    fact = Repo.one(from f in Fact, where: f.intent == "seed:tlon-what")
    {:ok, _} = Server.Dossier.forget_fact(fact)

    assert %{facts: 0} = Seed.ensure()
    # Still exactly one row for that intent — the tombstoned one, not a fresh copy.
    assert Repo.aggregate(from(f in Fact, where: f.intent == "seed:tlon-what"), :count) == 1
  end

  test "no default workspace yet → projects are skipped (facts still bank)" do
    # A pre-Bootstrap apply: no workspace exists, so projects have no home this run.
    assert %{projects: 0} = Seed.ensure()
  end
end
