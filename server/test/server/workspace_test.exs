defmodule Server.WorkspaceTest do
  # `Server.Workspace` schema + changesets (workspaces/orbis Slice 1). The DB is the guard
  # (§10): the closed sets on `type`/`scope` raise at insert, never re-checked here.
  # `knobs` round-trips through SQLite, so assertions read back through the DB.
  # Neither the scope nor the bench is a column any more — they are `workspace_repo` /
  # `workspace_agent` rows (UX slice 5), covered in `Server.WorkspacesTest`.
  use ExUnit.Case, async: false

  alias Server.Repo
  alias Server.Workspace

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "register_changeset/1" do
    test "a valid workspace inserts and its knobs round-trip through SQLite" do
      {:ok, workspace} =
        %{
          name: "Tlön",
          type: "code",
          scope: "machine",
          knobs: %{"accent" => "cyan"}
        }
        |> Workspace.register_changeset()
        |> Repo.insert()

      reloaded = Repo.get!(Workspace, workspace.id)
      assert reloaded.name == "Tlön"
      assert reloaded.type == "code"
      assert reloaded.scope == "machine"
      assert reloaded.knobs == %{"accent" => "cyan"}
      assert %DateTime{} = reloaded.created_at
    end

    test "defaults type/scope/knobs at the DB when omitted" do
      {:ok, workspace} =
        %{name: "Bare"} |> Workspace.register_changeset() |> Repo.insert()

      reloaded = Repo.get!(Workspace, workspace.id)
      assert reloaded.type == "code"
      assert reloaded.scope == "machine"
      assert reloaded.knobs == %{}
    end

    test "name is required" do
      refute Workspace.register_changeset(%{type: "code"}).valid?
    end

    test "an invalid type raises at the DB (the CHECK is the guard, not the changeset)" do
      cs = Workspace.register_changeset(%{name: "Bogus", type: "planet"})
      assert cs.valid?
      assert_raise Ecto.ConstraintError, fn -> Repo.insert(cs) end
    end
  end

  describe "edit_changeset/2" do
    setup do
      {:ok, workspace} =
        %{name: "Tlön", knobs: %{"a" => 1}} |> Workspace.register_changeset() |> Repo.insert()

      %{workspace: workspace}
    end

    test "casts mutable fields but not name/created_at", %{workspace: workspace} do
      cs = Workspace.edit_changeset(workspace, %{name: "Renamed", scope: "project", knobs: %{"k" => 1}})

      refute Ecto.Changeset.get_change(cs, :name)
      refute Ecto.Changeset.get_change(cs, :created_at)
      assert Ecto.Changeset.get_change(cs, :scope) == "project"
      assert Ecto.Changeset.get_change(cs, :knobs) == %{"k" => 1}
    end
  end
end
