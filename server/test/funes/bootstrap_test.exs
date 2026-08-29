defmodule Server.BootstrapTest do
  # Reshape slice A: boot-time integrity — the default workspace creates itself,
  # and no thread points at a workspace that isn't there (the live db carried a
  # thread → workspace_id=5 with only workspace 1 existing; remove_workspace orphaned it).
  use ExUnit.Case, async: false

  alias Server.Bootstrap
  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "an empty workspace table seeds the default workspace" do
    assert {:ok, workspace} = Bootstrap.ensure()
    assert workspace.name == "ficciones"
    assert workspace.scope == "machine"
    assert Enum.map(workspace.roster, & &1["name"]) == ["tertius", "hronir"]
    assert [%{id: id}] = Workspaces.all()
    assert id == workspace.id
  end

  test "an existing workspace is left untouched — no second seed, name preserved" do
    {:ok, tlon} = Workspaces.register(%{name: "Tlön", type: "code", scope: "machine", paths: [], roster: []})

    assert {:ok, workspace} = Bootstrap.ensure()
    assert workspace.id == tlon.id
    assert workspace.name == "Tlön"
    assert length(Workspaces.all()) == 1
  end

  test "threads with no workspace are repaired to the default" do
    {:ok, thread} = Channel.open_thread(%{title: "adrift"})
    assert thread.workspace_id == nil

    {:ok, workspace} = Bootstrap.ensure()
    assert Repo.get(Thread, thread.id).workspace_id == workspace.id
  end

  test "threads pointing at a dead workspace are repaired to the default" do
    {:ok, workspace} = Bootstrap.ensure()
    {:ok, thread} = Channel.open_thread(%{title: "orphan"})
    # The live-db drift this repairs was born under a suspended FK pragma (table
    # rebuilds, pre-integrity removes); reproduce it the same way. pool_size is 1
    # in test, so the pragma toggles the one real connection.
    Repo.query!("PRAGMA foreign_keys = OFF")
    Repo.query!("UPDATE thread SET workspace_id = 999 WHERE id = ?", [thread.id])
    Repo.query!("PRAGMA foreign_keys = ON")

    assert {:ok, %{id: workspace_id}} = Bootstrap.ensure()
    assert workspace_id == workspace.id
    assert Repo.get(Thread, thread.id).workspace_id == workspace.id
  end

  test "threads in a live non-default workspace are untouched" do
    {:ok, _default} = Bootstrap.ensure()
    {:ok, other} = Workspaces.register(%{name: "other", type: "code", scope: "project", paths: [], roster: []})
    {:ok, thread} = Channel.open_thread(%{title: "housed"})
    Repo.update_all(Thread, set: [workspace_id: other.id])

    assert {:ok, _} = Bootstrap.ensure()
    assert Repo.get(Thread, thread.id).workspace_id == other.id
  end

  test "ensure_safe on a healthy schema behaves like ensure" do
    assert {:ok, %Server.Workspace{}} = Bootstrap.ensure_safe()
  end

  describe "threads open into a workspace" do
    test "open_thread lands in the default workspace" do
      {:ok, workspace} = Bootstrap.ensure()

      {:ok, thread} = Channel.open_thread(%{title: "housed from birth"})
      assert thread.workspace_id == workspace.id
    end

    test "an explicit workspace_id is respected" do
      {:ok, _default} = Bootstrap.ensure()
      {:ok, other} = Workspaces.register(%{name: "other", type: "code", scope: "project", paths: [], roster: []})

      {:ok, thread} = Channel.open_thread(%{title: "placed", workspace_id: other.id})
      assert thread.workspace_id == other.id
    end

    test "a workline opens into the default workspace too" do
      {:ok, workspace} = Bootstrap.ensure()

      {:ok, thread} = Server.Workline.open(%{title: "tracked", slug: "housed-line"})
      assert thread.workspace_id == workspace.id
    end

    test "with no workspace at all, open_thread still works (workspace_id nil)" do
      {:ok, thread} = Channel.open_thread(%{title: "pre-bootstrap"})
      assert thread.workspace_id == nil
    end

    test "an explicit DANGLING workspace_id is refused by the FK itself (§10 single source)" do
      {:ok, _} = Bootstrap.ensure()

      # SQLite's own foreign key raises — never a mirrored app-side check that could drift.
      assert_raise Ecto.ConstraintError, fn ->
        Channel.open_thread(%{title: "nowhere", workspace_id: 999})
      end
    end
  end
end
