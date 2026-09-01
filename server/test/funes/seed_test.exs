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
