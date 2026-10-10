defmodule Server.WorktreeTest do
  # Per-thread git worktrees (Slice 4): a workline thread's code branch `work/<slug>` gets an
  # isolated checkout at `<repo>/.worktrees/<slug>`, so parallel crew never share a working tree.
  # Distinct path from the artifact-docs dir `work/<slug>/` — no collision. Real git, temp repos.
  use ExUnit.Case, async: false

  alias Server.Worktree

  doctest Server.Worktree

  setup do
    tmp = Path.join(System.tmp_dir!(), "worktree-test-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  describe "ensure/2" do
    test "creates an isolated checkout on branch work/<slug>", %{repo: repo, git: git} do
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

    test "a new worktree is seeded with the main checkout's deps where its lockfile is the same; a changed one is left to install",
         %{repo: repo, git: git} do
      for {lock, body} <- [{"server/mix.lock", "%{a: 1}\n"}, {"office/bun.lock", "{\"a\": 1}\n"}] do
        File.mkdir_p!(Path.dirname(Path.join(repo, lock)))
        File.write!(Path.join(repo, lock), body)
      end

      {_, 0} = git.(["add", "server/mix.lock", "office/bun.lock"])
      {_, 0} = git.(["commit", "-qm", "locks"])
      # on the work branch, office's lockfile changes (a dep added); server's does not
      {_, 0} = git.(["checkout", "-qb", "work/seeded"])
      File.write!(Path.join(repo, "office/bun.lock"), "{\"a\": 2}\n")
      {_, 0} = git.(["commit", "-qam", "bump"])
      {_, 0} = git.(["checkout", "-q", "-"])
      File.write!(Path.join(repo, "office/bun.lock"), "{\"a\": 1}\n")

      # the main checkout's installed deps (untracked)
      for dir <- ["server/deps/jason", "server/_build/dev", "office/node_modules/left-pad"] do
        File.mkdir_p!(Path.join(repo, dir))
        File.write!(Path.join([repo, dir, "x"]), "built\n")
      end

      assert {:ok, wt} = Worktree.ensure(repo, "seeded")
      assert File.read!(Path.join(wt, "server/deps/jason/x")) == "built\n"
      assert File.read!(Path.join(wt, "server/_build/dev/x")) == "built\n"
      refute File.exists?(Path.join(wt, "office/node_modules"))
    end

    test "a new work/<slug> starts from main, whatever branch the checkout is on", %{repo: repo, git: git} do
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["checkout", "-qb", "side"])
      File.write!(Path.join(repo, "side.txt"), "side work\n")
      {_, 0} = git.(["add", "side.txt"])
      {_, 0} = git.(["commit", "-qm", "side work"])

      assert {:ok, wt} = Worktree.ensure(repo, "from-main")
      refute File.exists?(Path.join(wt, "side.txt"))
      {main, 0} = git.(["rev-parse", "main"])
      {base, 0} = git.(["rev-parse", "work/from-main"])
      assert base == main
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
      bare = Path.join(System.tmp_dir!(), "not-a-repo-#{System.pid()}-#{System.unique_integer([:positive])}")
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

    test "a workline thread (has a slug) → a lazily-ensured .worktrees/<slug> checkout", %{
      repo: repo,
      ws: ws,
      project: p
    } do
      thread = struct!(Server.Thread, %{id: 1, workspace_id: ws.id, project_id: p.id, slug: "redis-cache", title: "t"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)
      assert wt == Worktree.path(repo, "redis-cache")
      assert File.exists?(Path.join(wt, ".git"))
    end

    # Andrew, 2026-09-08: "the minute it starts writing code it needs to be in a worktree" — a
    # thread with no slug (chat-born, or the machine thread) gets one named by its id, never the
    # main tree.
    test "a thread with NO slug gets a t<id> worktree — never the main tree", %{repo: repo, ws: ws, project: p} do
      thread = struct!(Server.Thread, %{id: 2, workspace_id: ws.id, project_id: p.id, slug: nil, title: "t"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)
      assert wt == Worktree.path(repo, "t2")
      assert File.exists?(Path.join(wt, ".git"))
    end

    test "no repo-bearing project anywhere → {:error, :no_repo}" do
      thread = struct!(Server.Thread, %{id: 3, workspace_id: nil, project_id: nil, slug: "x", title: "t"})
      assert {:error, :no_repo} = Server.worktree_for_thread(thread)
    end
  end

  describe "stranded/2" do
    test "nil when there is no checkout", %{repo: repo} do
      assert Worktree.stranded(repo, "ghost") == nil
    end

    test "nil for a checkout with nothing to lose", %{repo: repo} do
      {:ok, _} = Worktree.ensure(repo, "clean")
      assert Worktree.stranded(repo, "clean") == nil
    end

    test "names the unmerged commits a close would strand", %{repo: repo} do
      {:ok, wt} = Worktree.ensure(repo, "busy")
      File.write!(Path.join(wt, "work.txt"), "unmerged\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      assert Worktree.stranded(repo, "busy") =~ "unmerged"
    end
  end

  describe "remove/2 and rename/3 — the cleanup and promotion paths" do
    test "remove/2 drops a clean, unmerged-nothing worktree and its branch", %{repo: repo} do
      {:ok, wt} = Worktree.ensure(repo, "tidy")
      assert {:removed, ^wt} = Worktree.remove(repo, "tidy")
      refute File.exists?(wt)
      {out, 0} = System.cmd("git", ["-C", repo, "branch", "--list", "work/tidy"])
      assert String.trim(out) == ""
    end

    test "remove/2 KEEPS a worktree whose branch has unmerged commits, and says so", %{repo: repo, git: git} do
      {:ok, wt} = Worktree.ensure(repo, "busy")
      File.write!(Path.join(wt, "work.txt"), "unmerged\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      assert {:kept, reason} = Worktree.remove(repo, "busy")
      assert reason =~ "work/busy"
      assert File.exists?(wt)
      {out, 0} = git.(["branch", "--list", "work/busy"])
      assert String.trim(out) != ""
    end

    test "retire/2 takes a checkout down, unmerged commits and uncommitted changes and all, and keeps its branch", %{
      repo: repo,
      git: git
    } do
      {:ok, wt} = Worktree.ensure(repo, "dropped")
      File.write!(Path.join(wt, "work.txt"), "unmerged\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      File.write!(Path.join(wt, "half.txt"), "uncommitted\n")

      assert {:removed, ^wt} = Worktree.retire(repo, "dropped")
      refute File.exists?(wt)
      {out, 0} = git.(["branch", "--list", "work/dropped"])
      assert String.trim(out) != ""
      assert :none = Worktree.retire(repo, "dropped")
    end

    test "remove/2 drops a merged workline's worktree even with its docs folder on main", %{repo: repo, git: git} do
      # a workline's docs live at work/<slug>/ on main — the same spelling as its branch
      {:ok, _wt} = Worktree.ensure(repo, "docs")
      File.mkdir_p!(Path.join(repo, "work/docs"))
      File.write!(Path.join(repo, "work/docs/spec.md"), "spec\n")
      {_, 0} = git.(["add", "work/docs/spec.md"])
      {_, 0} = git.(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "spec"])
      assert {:removed, _} = Worktree.remove(repo, "docs")
    end

    test "remove/2 drops a worktree whose commits reached main by rebase — same change, new hash", %{
      repo: repo,
      git: git
    } do
      {:ok, wt} = Worktree.ensure(repo, "rebased")
      File.write!(Path.join(wt, "work.txt"), "landed\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      # main moves on, then the same change lands on it as a different commit (a rebase merge)
      File.write!(Path.join(repo, "other.txt"), "meanwhile\n")
      {_, 0} = git.(["add", "other.txt"])
      {_, 0} = git.(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "meanwhile"])
      {_, 0} = git.(["-c", "user.email=t@t", "-c", "user.name=t", "cherry-pick", "work/rebased"])
      assert {:removed, _} = Worktree.remove(repo, "rebased")
    end

    test "remove/2 reads the branch a checkout actually has, not only work/<name>", %{repo: repo, git: git} do
      wt = Worktree.path(repo, "by-hand")
      {_, 0} = git.(["worktree", "add", "-q", "-b", "office/by-hand", wt])
      assert {:removed, ^wt} = Worktree.remove(repo, "by-hand")
      {out, 0} = git.(["branch", "--list", "office/by-hand"])
      assert String.trim(out) == ""

      kept = Worktree.path(repo, "kept-by-hand")
      {_, 0} = git.(["worktree", "add", "-q", "-b", "office/kept", kept])
      File.write!(Path.join(kept, "work.txt"), "unmerged\n")
      {_, 0} = System.cmd("git", ["-C", kept, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", kept, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      assert {:kept, reason} = Worktree.remove(repo, "kept-by-hand")
      assert reason =~ "office/kept has unmerged commits"
    end

    test "remove/2 of a detached checkout of main's commit drops the checkout and never main", %{repo: repo, git: git} do
      wt = Worktree.path(repo, "t9")
      {_, 0} = git.(["worktree", "add", "-q", "--detach", wt])
      {main, 0} = git.(["symbolic-ref", "--short", "HEAD"])
      assert {:removed, ^wt} = Worktree.remove(repo, "t9")
      assert {_, 0} = git.(["rev-parse", "--verify", String.trim(main)])
    end

    test "holds/2 reads origin/main where there is one: merged there is merged, though this checkout lags", %{
      repo: repo,
      git: git
    } do
      {:ok, wt} = Worktree.ensure(repo, "landed")
      File.write!(Path.join(wt, "work.txt"), "landed\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "work.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "work"])
      assert Worktree.holds(repo, "landed") =~ "unmerged"

      {_, 0} = git.(["update-ref", "refs/remotes/origin/main", "work/landed"])
      assert Worktree.holds(repo, "landed") == nil
    end

    test "remove/2 on a worktree that never existed is :none", %{repo: repo} do
      assert :none = Worktree.remove(repo, "ghost")
    end

    test "rename/3 moves the checkout and renames the branch (promotion: t<id> → slug)", %{repo: repo, git: git} do
      {:ok, old} = Worktree.ensure(repo, "t7")
      assert {:ok, new} = Worktree.rename(repo, "t7", "redis-cache")
      assert new == Worktree.path(repo, "redis-cache")
      refute File.exists?(old)
      assert File.exists?(Path.join(new, ".git"))
      {out, 0} = git.(["branch", "--list", "work/redis-cache"])
      assert String.trim(out) != ""
      {out, 0} = git.(["branch", "--list", "work/t7"])
      assert String.trim(out) == ""
    end

    test "rename/3 with no source worktree is a no-op :none", %{repo: repo} do
      assert :none = Worktree.rename(repo, "t8", "whatever")
    end
  end

  test "a new worktree symlinks the main tree's gitignored dependency dirs (deps, node_modules), never _build", %{
    repo: repo
  } do
    for d <- ["deps", "node_modules", "_build"], do: File.mkdir_p!(Path.join(repo, d))
    File.write!(Path.join(repo, ".gitignore"), "deps\nnode_modules\n_build\n")
    assert {:ok, wt} = Worktree.ensure(repo, "linked")
    assert {:ok, target} = File.read_link(Path.join(wt, "deps"))
    assert target == Path.join(repo, "deps")
    assert {:ok, _} = File.read_link(Path.join(wt, "node_modules"))
    refute File.exists?(Path.join(wt, "_build"))
  end
end
