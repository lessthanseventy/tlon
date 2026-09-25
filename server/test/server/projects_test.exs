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

      {:ok, project} =
        Projects.register(%{workspace_id: ws.id, name: "cockpit", repos: [%{"name" => "ficciones", "path" => "."}]})

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

    test "last_used/1 is the project the operator last posted in, in this workspace" do
      {:ok, ws} = Workspaces.register(%{name: "Last used"})
      {:ok, other_ws} = Workspaces.register(%{name: "Away"})
      {:ok, a} = Projects.register(%{workspace_id: ws.id, name: "ficciones"})
      {:ok, b} = Projects.register(%{workspace_id: ws.id, name: "excessibility"})
      {:ok, away} = Projects.register(%{workspace_id: other_ws.id, name: "elsewhere"})

      assert Projects.last_used(ws.id) == nil

      {:ok, one} = Server.Channel.open_thread(%{title: "one", workspace_id: ws.id, project_id: a.id})
      {:ok, two} = Server.Channel.open_thread(%{title: "two", workspace_id: ws.id, project_id: b.id})
      {:ok, _} = Server.Channel.open_thread(%{title: "no project", workspace_id: ws.id})
      {:ok, far} = Server.Channel.open_thread(%{title: "away", workspace_id: other_ws.id, project_id: away.id})
      {:ok, _} = Server.Channel.post(%{thread_id: two.id, author: "andrew", body: "first"})
      {:ok, _} = Server.Channel.post(%{thread_id: one.id, author: "andrew", body: "then this"})
      {:ok, _} = Server.Channel.post(%{thread_id: far.id, author: "andrew", body: "elsewhere"})
      # a thread the machine made later (an import's memory thread) is not "used"
      {:ok, _} = Server.Channel.open_thread(%{title: "Claude Code memory", workspace_id: ws.id, project_id: b.id})

      assert Projects.last_used(ws.id) == a.id
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

  describe "repo_for_thread/1 — resolve a thread to its primary repo dir (Slice 4, the worktree base)" do
    alias Server.Channel

    test "the thread's project's FIRST repo path, ~-expanded", %{workspace: ws} do
      repos = [%{"name" => "ficciones", "path" => "~/projects/ficciones"}, %{"name" => "other", "path" => "/x"}]
      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit", repos: repos})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})

      assert {:ok, path} = Projects.repo_for_thread(t)
      assert path == Path.expand("~/projects/ficciones")
    end

    test "with no project_id, falls back to the workspace's first repo-bearing project", %{workspace: ws} do
      # An earlier repo-less project is skipped; the resolver finds the one that has repos.
      {:ok, _empty} = Projects.register(%{workspace_id: ws.id, name: "empty"})

      {:ok, _p} =
        Projects.register(%{workspace_id: ws.id, name: "has-repo", repos: [%{"name" => "r", "path" => "/srv/r"}]})

      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id})

      assert {:ok, "/srv/r"} = Projects.repo_for_thread(t)
    end

    test "an explicit project with NO repos resolves to :no_repo (never silently borrows another's)", %{workspace: ws} do
      {:ok, other} =
        Projects.register(%{workspace_id: ws.id, name: "other", repos: [%{"name" => "r", "path" => "/srv/r"}]})

      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "cockpit", repos: []})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})
      _ = other

      assert {:error, :no_repo} = Projects.repo_for_thread(t)
    end

    test "no repo-bearing project anywhere in the workspace → {:error, :no_repo}", %{workspace: ws} do
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id})
      assert {:error, :no_repo} = Projects.repo_for_thread(t)
    end

    test "a thread that names its repo works there, not in the project's first" do
      {:ok, ws} = Workspaces.register(%{name: "own-repo"})

      repos = [
        %{"name" => "ficciones", "path" => "~/projects/ficciones"},
        %{"name" => "menard", "path" => "~/projects/menard"}
      ]

      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "tlon", repos: repos})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id, repo: "~/projects/menard"})

      assert {:ok, path} = Projects.repo_for_thread(t)
      assert path == Path.expand("~/projects/menard")
      assert Projects.read_dirs(t) == [Path.expand("~/projects/ficciones")]
    end

    test "read_dirs are the project's other checkouts: never the thread's own repo, never a glob" do
      {:ok, ws} = Workspaces.register(%{name: "read-dirs"})

      repos = [
        %{"name" => "ficciones", "path" => "~/projects/ficciones"},
        %{"name" => "scope", "path" => "modules/*"},
        %{"name" => "mix_master", "path" => "/p/mix_master"}
      ]

      {:ok, p} = Projects.register(%{workspace_id: ws.id, name: "tlon", repos: repos})
      {:ok, t} = Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})

      assert Projects.read_dirs(t) == ["/p/mix_master"]
      assert Projects.read_dirs(%{t | project_id: nil}) == []
    end
  end

  describe "repo_for_workspace/1 — the STACK panel's per-workspace git dir" do
    test "the workspace's first repo-bearing project's ~-expanded primary repo", %{workspace: ws} do
      {:ok, _empty} = Projects.register(%{workspace_id: ws.id, name: "empty"})

      {:ok, _p} =
        Projects.register(%{workspace_id: ws.id, name: "client", repos: [%{"name" => "r", "path" => "~/projects/x"}]})

      assert {:ok, path} = Projects.repo_for_workspace(ws.id)
      assert path == Path.expand("~/projects/x")
    end

    test "no repo-bearing project → {:error, :no_repo}; a nil id too", %{workspace: ws} do
      assert {:error, :no_repo} = Projects.repo_for_workspace(ws.id)
      assert {:error, :no_repo} = Projects.repo_for_workspace(nil)
    end
  end

  describe "repo_for_thread/1 — a scope glob is not a checkout" do
    test "a glob path (modules/*) resolves to :no_repo, never a worktree under $HOME", %{workspace: ws} do
      {:ok, p} =
        Projects.register(%{
          workspace_id: ws.id,
          name: "general",
          repos: [%{"name" => "modules/*", "path" => "modules/*"}]
        })

      {:ok, t} = Server.Channel.open_thread(%{title: "w", workspace_id: ws.id, project_id: p.id})

      assert {:error, :no_repo} = Projects.repo_for_thread(t)
    end
  end
end
