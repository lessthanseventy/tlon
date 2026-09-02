defmodule Server.WorktreeTest do
  # Per-thread git worktrees (Slice 4): a workline thread's code branch `work/<slug>` gets an
  # isolated checkout at `<repo>/.worktrees/<slug>`, so parallel crew never share a working tree.
  # Distinct path from the artifact-docs dir `work/<slug>/` — no collision. Real git, temp repos.
  use ExUnit.Case, async: false

  alias Server.Worktree

  setup do
    tmp = Path.join(System.tmp_dir!(), "worktree-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    git = fn args -> System.cmd("git", ["-C", tmp | args], stderr_to_stdout: true) end
    {_, 0} = git.(["init", "-q"])
    {_, 0} = git.(["config", "user.email", "test@test"])
    {_, 0} = git.(["config", "user.name", "test"])
    # A worktree branches off HEAD, so the repo needs one commit.
    File.write!(Path.join(tmp, "README"), "seed\n")
    {_, 0} = git.(["add", "README"])
    {_, 0} = git.(["commit", "-qm", "seed"])

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{repo: tmp, git: git}
  end

  describe "pure helpers" do
    test "branch/1 matches the workline's work/<slug> convention" do
      assert Worktree.branch("redis-cache") == "work/redis-cache"
    end

    test "path/2 places the checkout under <repo>/.worktrees/<slug>" do
      assert Worktree.path("/r", "redis-cache") == "/r/.worktrees/redis-cache"
    end
  end

  describe "ensure/2" do
    test "creates an isolated checkout on branch work/<slug>, off HEAD", %{repo: repo, git: git} do
      assert {:ok, wt} = Worktree.ensure(repo, "redis-cache")
      assert wt == Worktree.path(repo, "redis-cache")
      # A linked worktree carries a `.git` FILE pointing back at the shared gitdir.
      assert File.exists?(Path.join(wt, ".git"))
      assert File.read!(Path.join(wt, "README")) == "seed\n"
      # The branch now exists and is what the worktree has checked out.
      assert {_, 0} = git.(["rev-parse", "--verify", "work/redis-cache"])
      {head, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true)
      assert String.trim(head) == "work/redis-cache"
    end

    test "is idempotent — a second call returns the same path, no error, no churn", %{repo: repo} do
      assert {:ok, wt} = Worktree.ensure(repo, "redis-cache")
      assert {:ok, ^wt} = Worktree.ensure(repo, "redis-cache")
    end

    test "reuses a pre-existing work/<slug> branch instead of failing to re-create it", %{repo: repo, git: git} do
      {_, 0} = git.(["branch", "work/preexist"])
      assert {:ok, wt} = Worktree.ensure(repo, "preexist")
      {head, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--abbrev-ref", "HEAD"], stderr_to_stdout: true)
      assert String.trim(head) == "work/preexist"
    end

    test "ignores .worktrees/ repo-locally via .git/info/exclude (never a committed .gitignore)", %{repo: repo} do
      {:ok, _wt} = Worktree.ensure(repo, "redis-cache")
      assert File.read!(Path.join(repo, ".git/info/exclude")) =~ ".worktrees/"
      refute File.exists?(Path.join(repo, ".gitignore"))
      # The worktree dir is not surfaced as an untracked change in the main tree.
      {status, 0} = System.cmd("git", ["-C", repo, "status", "--porcelain"], stderr_to_stdout: true)
      refute status =~ ".worktrees"
    end

    test "a traversing/empty slug is refused before touching git", %{repo: repo} do
      assert {:error, :bad_slug} = Worktree.ensure(repo, "../escape")
      assert {:error, :bad_slug} = Worktree.ensure(repo, "")
      assert {:error, :bad_slug} = Worktree.ensure(repo, "Has Spaces")
    end

    test "a non-git directory is a clean error, not a raise", %{} do
      bare = Path.join(System.tmp_dir!(), "not-a-repo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(bare)
      on_exit(fn -> File.rm_rf!(bare) end)
      assert {:error, :not_a_repo} = Worktree.ensure(bare, "x")
    end
  end

  describe "Server.worktree_for_thread/1 (facade: thread → project repo → ensured worktree)" do
    setup %{repo: repo} do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Home"})

      {:ok, project} =
        Server.Projects.register(%{workspace_id: ws.id, name: "proj", repos: [%{"name" => "r", "path" => repo}]})

      %{ws: ws, project: project}
    end

    test "a workline thread (has a slug) → a lazily-ensured .worktrees/<slug> checkout", %{repo: repo, ws: ws, project: p} do
      thread = struct!(Server.Thread, %{id: 1, workspace_id: ws.id, project_id: p.id, slug: "redis-cache", title: "t"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)
      assert wt == Worktree.path(repo, "redis-cache")
      assert File.exists?(Path.join(wt, ".git"))
    end

    test "a thread with NO slug falls back to the project repo itself", %{repo: repo, ws: ws, project: p} do
      thread = struct!(Server.Thread, %{id: 2, workspace_id: ws.id, project_id: p.id, slug: nil, title: "t"})
      assert {:ok, ^repo} = Server.worktree_for_thread(thread)
    end

    test "no repo-bearing project anywhere → {:error, :no_repo}" do
      thread = struct!(Server.Thread, %{id: 3, workspace_id: nil, project_id: nil, slug: "x", title: "t"})
      assert {:error, :no_repo} = Server.worktree_for_thread(thread)
    end
  end
end
