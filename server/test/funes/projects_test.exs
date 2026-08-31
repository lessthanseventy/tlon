defmodule Server.ProjectsTest do
  # The `Server.Projects` context (Workspace ▸ Project ▸ Thread, 2026-08-30): the write
  # pipe (changeset |> insert |> Bus.announce) and reads. The DB is the bus (§10):
  # assertions read back through it.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Project
  alias Server.Projects
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, workspace: ws}
  end

  describe "register/1" do
    test "inserts under a workspace and announces on the projects topic", %{workspace: ws} do
      Bus.subscribe_projects()

      {:ok, project} = Projects.register(%{workspace_id: ws.id, name: "cockpit", repos: [%{"name" => "ficciones", "path" => "."}]})

      assert %Project{} = project
      assert project.name == "cockpit"
      assert project.workspace_id == ws.id
      assert project.repos == [%{"name" => "ficciones", "path" => "."}]
      assert_receive {:project_registered, %Project{name: "cockpit"}}
    end

    test "a duplicate name WITHIN a workspace returns {:error, changeset}", %{workspace: ws} do
      {:ok, _} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      assert {:error, %Ecto.Changeset{}} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
    end

    test "the SAME name in a DIFFERENT workspace is fine", %{workspace: ws} do
      {:ok, ws2} = Workspaces.register(%{name: "Work"})
      {:ok, _} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      assert {:ok, %Project{}} = Projects.register(%{workspace_id: ws2.id, name: "cockpit"})
    end

    test "workspace_id and name are required" do
      assert {:error, %Ecto.Changeset{}} = Projects.register(%{name: "x"})
      assert {:error, %Ecto.Changeset{}} = Projects.register(%{workspace_id: 1})
    end
  end

  describe "reads" do
    test "in_workspace/1 lists a workspace's projects oldest-first", %{workspace: ws} do
      {:ok, a} = Projects.register(%{workspace_id: ws.id, name: "a"})
      {:ok, b} = Projects.register(%{workspace_id: ws.id, name: "b"})
      assert Enum.map(Projects.in_workspace(ws.id), & &1.id) == [a.id, b.id]
    end

    test "by_name/2 finds within the workspace", %{workspace: ws} do
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      assert %Project{id: id} = Projects.by_name(ws.id, "cockpit")
      assert id == p.id
      assert Projects.by_name(ws.id, "nope") == nil
    end
  end

  describe "edit/2 & remove/1" do
    test "edit updates mutable fields and announces", %{workspace: ws} do
      Bus.subscribe_projects()
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      {:ok, edited} = Projects.edit(p, %{name: "cockpit2", knobs: %{"ticket_backend" => "local"}})
      assert edited.name == "cockpit2"
      assert edited.knobs == %{"ticket_backend" => "local"}
      assert_receive {:project_edited, %Project{name: "cockpit2"}}
    end

    test "remove deletes an empty project and announces", %{workspace: ws} do
      Bus.subscribe_projects()
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      assert {:ok, _} = Projects.remove(p)
      assert Projects.get(p.id) == nil
      assert_receive {:project_removed, %Project{}}
    end

    test "remove is refused while a thread belongs to the project", %{workspace: ws} do
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit"})
      {:ok, _thread} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id, project_id: p.id})
      assert {:error, :has_threads} = Projects.remove(p)
    end
  end
end
