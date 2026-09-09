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
      {:ok, workspace} = Workspaces.register(%{name: "Tlön", roster: [%{"name" => "a"}]})

      {:ok, edited} = Workspaces.edit(workspace, %{roster: [%{"name" => "b"}], knobs: %{"accent" => "cyan"}})

      assert edited.roster == [%{"name" => "b"}]
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

  describe "the repos table (UX slice 5) — the git-tracked scope as rows" do
    test "repos come back in the order the operator arranged them, and a new one appends" do
      {:ok, ws} = Workspaces.register(%{name: "Tlön", repos: ["modules/*", "docs/*"]})

      assert ["modules/*", "docs/*"] = ws.id |> Workspaces.repos() |> Enum.map(& &1.path)

      {:ok, _} = Workspaces.add_repo(ws.id, %{path: "priv/*"})
      assert ["modules/*", "docs/*", "priv/*"] = ws.id |> Workspaces.repos() |> Enum.map(& &1.path)
    end

    test "a repo carries the remote and default branch a bare glob had nowhere to record" do
      {:ok, ws} = Workspaces.register(%{name: "Tlön"})

      {:ok, repo} =
        Workspaces.add_repo(ws.id, %{
          path: "/home/andrew/projects/ficciones",
          remote: "git@github.com:andrew/ficciones.git",
          default_branch: "main"
        })

      assert repo.remote == "git@github.com:andrew/ficciones.git"
      assert repo.default_branch == "main"
    end

    test "remote and default_branch are nil, not invented, for a migrated glob" do
      {:ok, ws} = Workspaces.register(%{name: "Tlön", repos: ["modules/*"]})
      [repo] = Workspaces.repos(ws.id)

      assert repo.remote == nil
      assert repo.default_branch == nil
    end

    test "the same path twice in one workspace is refused; the same path in another is not" do
      {:ok, a} = Workspaces.register(%{name: "A", repos: ["modules/*"]})
      {:ok, b} = Workspaces.register(%{name: "B"})

      assert {:error, %Ecto.Changeset{}} = Workspaces.add_repo(a.id, %{path: "modules/*"})
      assert {:ok, _} = Workspaces.add_repo(b.id, %{path: "modules/*"})
    end

    test "a repo change announces the WORKSPACE — the Bus's struct set stays closed" do
      {:ok, ws} = Workspaces.register(%{name: "Tlön"})
      Bus.subscribe_workspaces()

      {:ok, repo} = Workspaces.add_repo(ws.id, %{path: "modules/*"})
      assert_receive {:workspace_edited, %Workspace{id: id}} when id == ws.id

      {:ok, _} = Workspaces.edit_repo(repo, %{default_branch: "main"})
      assert_receive {:workspace_edited, %Workspace{}}

      {:ok, _} = Workspaces.remove_repo(repo)
      assert_receive {:workspace_edited, %Workspace{}}
      assert Workspaces.repos(ws.id) == []
    end

    test "replace_repos overwrites the whole scope — the old JSON column's semantics, kept" do
      {:ok, ws} = Workspaces.register(%{name: "Tlön", repos: ["a/*", "b/*"]})

      :ok = Workspaces.replace_repos(ws.id, ["c/*"])
      assert ["c/*"] = ws.id |> Workspaces.repos() |> Enum.map(& &1.path)
    end

    test "removing a workspace takes its repos with it" do
      {:ok, _keep} = Workspaces.register(%{name: "keep"})
      {:ok, doomed} = Workspaces.register(%{name: "doomed", repos: ["a/*"]})

      {:ok, _} = Workspaces.remove(doomed)
      assert Workspaces.repos(doomed.id) == []
    end

    test "repos_by_workspace answers the whole picker in one read" do
      {:ok, a} = Workspaces.register(%{name: "A", repos: ["a/*"]})
      {:ok, b} = Workspaces.register(%{name: "B", repos: ["b/*", "b2/*"]})

      by_ws = Workspaces.repos_by_workspace([a.id, b.id])

      assert Enum.map(by_ws[a.id], & &1.path) == ["a/*"]
      assert Enum.map(by_ws[b.id], & &1.path) == ["b/*", "b2/*"]
    end
  end
end
