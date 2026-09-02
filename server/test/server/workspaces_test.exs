defmodule Server.WorkspacesTest do
  # The `Server.Workspaces` context (workspaces/orbis Slice 1): the write pipe
  # (changeset |> insert |> Bus.announce) and the reads aleph drives its
  # picker/survey from. The DB is the bus (§10): assertions read back through it.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Workspace
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "register/1" do
    test "inserts and announces on the workspaces topic" do
      Bus.subscribe_workspaces()

      {:ok, workspace} =
        Workspaces.register(%{name: "Tlön", type: "code", paths: ["modules/*"]})

      assert %Workspace{} = workspace
      assert workspace.name == "Tlön"
      assert_receive {:workspace_registered, %Workspace{name: "Tlön"}}
    end

    test "a duplicate name returns {:error, changeset}, not a crash" do
      {:ok, _} = Workspaces.register(%{name: "Tlön"})
      assert {:error, %Ecto.Changeset{}} = Workspaces.register(%{name: "Tlön"})
    end
  end

  describe "all/0" do
    test "lists workspaces newest-first" do
      {:ok, _a} = Workspaces.register(%{name: "First"})
      {:ok, _b} = Workspaces.register(%{name: "Second"})

      assert ["Second", "First"] == Enum.map(Workspaces.all(), & &1.name)
    end
  end

  describe "get/1 and by_name/1" do
    test "return the workspace, or nil when absent" do
      {:ok, workspace} = Workspaces.register(%{name: "Tlön"})

      assert Workspaces.get(workspace.id).name == "Tlön"
      assert Workspaces.by_name("Tlön").id == workspace.id
      assert Workspaces.get(-1) == nil
      assert Workspaces.by_name("nope") == nil
    end
  end

  describe "edit/2" do
    test "updates mutable fields and announces" do
      Bus.subscribe_workspaces()
      {:ok, workspace} = Workspaces.register(%{name: "Tlön", paths: ["a"]})

      {:ok, edited} = Workspaces.edit(workspace, %{paths: ["b"], knobs: %{"accent" => "cyan"}})

      assert edited.paths == ["b"]
      assert Workspaces.get(workspace.id).knobs == %{"accent" => "cyan"}
      assert_receive {:workspace_edited, %Workspace{}}
    end
  end

  describe "remove/1" do
    test "deletes the workspace, rehouses its threads in the oldest remaining, announces" do
      Bus.subscribe_workspaces()
      {:ok, keep} = Workspaces.register(%{name: "keep"})
      {:ok, doomed} = Workspaces.register(%{name: "doomed"})
      {:ok, thread} = Server.Channel.open_thread(%{title: "tenant"})
      Server.Repo.update_all(Server.Thread, set: [workspace_id: doomed.id])

      {:ok, _} = Workspaces.remove(doomed)

      assert Workspaces.get(doomed.id) == nil
      assert Server.Repo.get(Server.Thread, thread.id).workspace_id == keep.id
      assert_receive {:workspace_removed, %Workspace{}}
    end

    test "the last workspace is refused — threads must always have a home" do
      {:ok, only} = Workspaces.register(%{name: "only"})

      assert {:error, :last_workspace} = Workspaces.remove(only)
      assert Workspaces.get(only.id)
    end
  end
end
