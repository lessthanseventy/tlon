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
      assert {:error, :einval} = File.read_link(Path.join(wt, "server/deps"))
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

  describe "ensure/2 — a checkout's gitfile always resolves" do
    test "concurrent ensures of one slug all succeed and leave one working checkout", %{repo: repo} do
      results =
        1..8
        |> Enum.map(fn _ -> Task.async(fn -> Worktree.ensure(repo, "racy") end) end)
        |> Task.await_many(30_000)

      wt = Worktree.path(repo, "racy")
      assert Enum.all?(results, &(&1 == {:ok, wt})), inspect(results)
      assert {_, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--git-dir"], stderr_to_stdout: true)
      assert File.ls!(Path.join(repo, ".git/worktrees")) == ["racy"]
    end

    test "an existing checkout whose gitfile names a phantom gitdir is repaired", %{repo: repo} do
      {:ok, wt} = Worktree.ensure(repo, "broken")
      gitfile = Path.join(wt, ".git")
      File.write!(gitfile, String.trim_trailing(File.read!(gitfile)) <> "1\n")
      assert {_, 128} = System.cmd("git", ["-C", wt, "rev-parse", "--git-dir"], stderr_to_stdout: true)

      assert {:ok, ^wt} = Worktree.ensure(repo, "broken")
      assert {_, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--git-dir"], stderr_to_stdout: true)
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
      {git_dir, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--absolute-git-dir"])
      assert File.read!(Path.join(String.trim(git_dir), "tlon-thread")) == "1\n"
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

    test "a wake fast-forwards a checkout with no work of its own; own commits are told to the thread once",
         %{repo: repo, git: git, ws: ws, project: p} do
      remote = repo <> "-origin.git"
      {_, 0} = System.cmd("git", ["init", "-q", "--bare", remote])
      on_exit(fn -> File.rm_rf!(remote) end)
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["remote", "add", "origin", remote])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      {:ok, thread} = Server.Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: p.id, slug: "wake"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)

      File.write!(Path.join(repo, "NEW"), "more\n")
      {_, 0} = git.(["add", "NEW"])
      {_, 0} = git.(["commit", "-qm", "main moves"])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])
      # the facade ensures; only a wake (Spawn) catches up, never a tool call under a running pane
      assert {:ok, ^wt} = Server.worktree_for_thread(thread)
      refute File.exists?(Path.join(wt, "NEW"))
      assert Server.catch_up_worktree(thread, wt) == :ok
      assert File.exists?(Path.join(wt, "NEW"))

      File.write!(Path.join(wt, "MINE"), "mine\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "MINE"])
      {_, 0} = System.cmd("git", ["-C", wt, "commit", "-qm", "mine"])
      # own commits on top of main: nothing to explain
      assert Server.catch_up_worktree(thread, wt) == :ok
      assert [] = Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "1 commit"))

      File.write!(Path.join(repo, "NEW2"), "more\n")
      {_, 0} = git.(["add", "NEW2"])
      {_, 0} = git.(["commit", "-qm", "main moves again"])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])
      assert Server.catch_up_worktree(thread, wt) == :ok
      assert Server.catch_up_worktree(thread, wt) == :ok

      told = Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "1 commit"))
      assert [%{kind: "notice"}] = told
    end

    test "a dirty checkout is told again after it was cleaned and moved", %{repo: repo, git: git, ws: ws, project: p} do
      remote = repo <> "-origin.git"
      {_, 0} = System.cmd("git", ["init", "-q", "--bare", remote])
      on_exit(fn -> File.rm_rf!(remote) end)
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["remote", "add", "origin", remote])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      {:ok, thread} = Server.Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: p.id, slug: "redirty"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)
      told = fn -> Enum.count(Server.Channel.thread_messages(thread), &(&1.body =~ "uncommitted")) end

      File.write!(Path.join(wt, "SCRATCH"), "x\n")
      assert Server.catch_up_worktree(thread, wt) == :ok
      assert told.() == 1

      File.rm!(Path.join(wt, "SCRATCH"))
      assert Server.catch_up_worktree(thread, wt) == :ok

      File.write!(Path.join(wt, "SCRATCH"), "x\n")
      assert Server.catch_up_worktree(thread, wt) == :ok
      assert told.() == 2
    end

    test "a catch-up that errors is told to the thread once", %{repo: repo, git: git, ws: ws, project: p} do
      remote = repo <> "-origin.git"
      {_, 0} = System.cmd("git", ["init", "-q", "--bare", remote])
      on_exit(fn -> File.rm_rf!(remote) end)
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["remote", "add", "origin", remote])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      {:ok, thread} = Server.Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: p.id, slug: "broken"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)

      File.write!(Path.join(repo, "NEW"), "more\n")
      {_, 0} = git.(["add", "NEW"])
      {_, 0} = git.(["commit", "-qm", "main moves"])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      Application.put_env(:server, :git_cmd, fn cmd, args, opts ->
        if "merge" in args, do: {"fatal: Unable to create index.lock", 128}, else: System.cmd(cmd, args, opts)
      end)

      on_exit(fn -> Application.delete_env(:server, :git_cmd) end)

      assert Server.catch_up_worktree(thread, wt) == :ok
      assert Server.catch_up_worktree(thread, wt) == :ok

      assert [%{kind: "notice"}] =
               Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "could not be moved"))
    end

    test "own commits are not told when git cannot say whether main moved", %{
      repo: repo,
      git: git,
      ws: ws,
      project: p
    } do
      remote = repo <> "-origin.git"
      {_, 0} = System.cmd("git", ["init", "-q", "--bare", remote])
      on_exit(fn -> File.rm_rf!(remote) end)
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["remote", "add", "origin", remote])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      {:ok, thread} = Server.Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: p.id, slug: "mute"})
      assert {:ok, wt} = Server.worktree_for_thread(thread)
      File.write!(Path.join(wt, "MINE"), "mine\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "MINE"])
      {_, 0} = System.cmd("git", ["-C", wt, "commit", "-qm", "mine"])
      File.write!(Path.join(repo, "NEW"), "more\n")
      {_, 0} = git.(["add", "NEW"])
      {_, 0} = git.(["commit", "-qm", "main moves"])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])

      Application.put_env(:server, :git_cmd, fn cmd, args, opts ->
        if "HEAD..origin/main" in args, do: {"fatal: boom", 128}, else: System.cmd(cmd, args, opts)
      end)

      on_exit(fn -> Application.delete_env(:server, :git_cmd) end)

      assert Server.catch_up_worktree(thread, wt) == :ok
      assert [] = Enum.filter(Server.Channel.thread_messages(thread), &(&1.body =~ "1 commit"))
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

    # GitHub's rebase-merge gives every commit a new SHA and can fold a commit's files into a
    # neighbour's diff, so git cherry's patch-id check misses it. The change is on origin/main as
    # the same file contents, so it is not stranded.
    test "nil when a branch's commits were rebase-merged to origin/main — same files, new patch", %{
      repo: repo,
      git: git
    } do
      {_, 0} = git.(["checkout", "-qb", "work/landed"])
      File.write!(Path.join(repo, "work.txt"), "change\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "the change"])
      {_, 0} = git.(["checkout", "-q", "-"])

      # main lands the same file contents in a commit with a different diff (a neighbouring file too)
      File.write!(Path.join(repo, "work.txt"), "change\n")
      File.write!(Path.join(repo, "other.txt"), "extra\n")
      {_, 0} = git.(["add", "work.txt", "other.txt"])
      {_, 0} = git.(["commit", "-qm", "rebase-merged"])
      {_, 0} = git.(["update-ref", "refs/remotes/origin/main", "HEAD"])

      {:ok, _} = Worktree.ensure(repo, "landed")
      assert Worktree.stranded(repo, "landed") == nil
    end

    # Commit A writes work.txt, commit B rewrites it; main lands only the final contents. A's own
    # version of the file never matches main, but the branch tip does: it has landed.
    test "nil when a later commit rewrites an earlier commit's file and the tip is on origin/main", %{
      repo: repo,
      git: git
    } do
      {_, 0} = git.(["checkout", "-qb", "work/superseded"])
      File.write!(Path.join(repo, "work.txt"), "first\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "first draft"])
      File.write!(Path.join(repo, "work.txt"), "final\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "rewrite"])
      {_, 0} = git.(["checkout", "-q", "-"])

      File.write!(Path.join(repo, "work.txt"), "final\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "squash-merged"])
      {_, 0} = git.(["update-ref", "refs/remotes/origin/main", "HEAD"])

      {:ok, _} = Worktree.ensure(repo, "superseded")
      assert Worktree.stranded(repo, "superseded") == nil
    end

    test "still names a branch whose change is NOT on origin/main, even if other files match", %{
      repo: repo,
      git: git
    } do
      {_, 0} = git.(["checkout", "-qb", "work/diverged"])
      File.write!(Path.join(repo, "work.txt"), "mine\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "my change"])
      {_, 0} = git.(["checkout", "-q", "-"])

      File.write!(Path.join(repo, "work.txt"), "theirs\n")
      {_, 0} = git.(["add", "work.txt"])
      {_, 0} = git.(["commit", "-qm", "main's different change"])
      {_, 0} = git.(["update-ref", "refs/remotes/origin/main", "HEAD"])

      {:ok, _} = Worktree.ensure(repo, "diverged")
      assert Worktree.stranded(repo, "diverged") =~ "unmerged"
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
      # the uncommitted file went onto the branch, not into the void
      assert {_, 0} = git.(["cat-file", "-e", "work/dropped:half.txt"])
    end

    test "retire/2 names a detached checkout's commits before it goes", %{repo: repo, git: git} do
      {:ok, wt} = Worktree.ensure(repo, "loose")
      {_, 0} = System.cmd("git", ["-C", wt, "checkout", "-q", "--detach"])
      File.write!(Path.join(wt, "loose.txt"), "detached work\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "loose.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "loose"])

      {sha, 0} = System.cmd("git", ["-C", wt, "rev-parse", "--short", "HEAD"])
      assert {:removed, _} = Worktree.retire(repo, "loose")
      assert {_, 0} = git.(["cat-file", "-e", "rescued/loose-#{String.trim(sha)}:loose.txt"])
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

  test "a new worktree links only the shell's store-backed node_modules; mutable deps are never shared", %{
    repo: repo
  } do
    for d <- ["deps", "node_modules", "_build", "modules/desktop/shell/node_modules"],
        do: File.mkdir_p!(Path.join(repo, d))

    File.write!(Path.join(repo, ".gitignore"), "deps\nnode_modules\n_build\n")
    assert {:ok, wt} = Worktree.ensure(repo, "linked")

    assert {:ok, target} = File.read_link(Path.join(wt, "modules/desktop/shell/node_modules"))
    assert target == Path.join(repo, "modules/desktop/shell/node_modules")
    for d <- ["deps", "node_modules", "_build"], do: refute(File.exists?(Path.join(wt, d)))
  end

  describe "catch_up/1 — a thread checkout with no work of its own follows origin/main" do
    setup %{repo: repo, git: git} do
      remote = repo <> "-origin.git"
      {_, 0} = System.cmd("git", ["init", "-q", "--bare", remote])
      on_exit(fn -> File.rm_rf!(remote) end)
      {_, 0} = git.(["branch", "-M", "main"])
      {_, 0} = git.(["remote", "add", "origin", remote])
      {_, 0} = git.(["push", "-q", "origin", "main"])
      {_, 0} = git.(["fetch", "-q", "origin"])
      {:ok, wt} = Worktree.ensure(repo, "x")
      wt_git = fn args -> System.cmd("git", ["-C", wt | args], stderr_to_stdout: true) end

      advance = fn ->
        File.write!(Path.join(repo, "NEW"), "more\n")
        {_, 0} = git.(["add", "NEW"])
        {_, 0} = git.(["commit", "-qm", "main moves"])
        {_, 0} = git.(["push", "-q", "origin", "main"])
        {_, 0} = git.(["fetch", "-q", "origin"])
      end

      head = fn g ->
        {out, 0} = g.(["rev-parse", "HEAD"])
        String.trim(out)
      end

      %{wt: wt, wt_git: wt_git, advance: advance, head: head}
    end

    test "no commit of its own → HEAD becomes origin/main", ctx do
      ctx.advance.()
      refute ctx.head.(ctx.wt_git) == ctx.head.(ctx.git)
      assert :moved = Worktree.catch_up(ctx.wt)
      assert ctx.head.(ctx.wt_git) == ctx.head.(ctx.git)
      assert File.exists?(Path.join(ctx.wt, "NEW"))
      assert :level = Worktree.catch_up(ctx.wt)
    end

    test "a commit of its own → untouched, the ahead count said", ctx do
      File.write!(Path.join(ctx.wt, "MINE"), "mine\n")
      {_, 0} = ctx.wt_git.(["add", "MINE"])
      {_, 0} = ctx.wt_git.(["commit", "-qm", "mine"])
      ctx.advance.()
      before = ctx.head.(ctx.wt_git)
      assert {:ahead, 1} = Worktree.catch_up(ctx.wt)
      assert ctx.head.(ctx.wt_git) == before
    end

    test "a dirty tree → untouched, and said", ctx do
      ctx.advance.()
      before = ctx.head.(ctx.wt_git)
      File.write!(Path.join(ctx.wt, "README"), "edited\n")
      assert :dirty = Worktree.catch_up(ctx.wt)
      assert ctx.head.(ctx.wt_git) == before
    end

    test "a detached HEAD stays put", ctx do
      ctx.advance.()
      before = ctx.head.(ctx.wt_git)
      {_, 0} = ctx.wt_git.(["checkout", "-q", "--detach"])
      assert :detached = Worktree.catch_up(ctx.wt)
      assert ctx.head.(ctx.wt_git) == before
    end

    test "the same state is reported once", ctx do
      assert Worktree.report_once?(ctx.wt, "ahead:abc:1")
      refute Worktree.report_once?(ctx.wt, "ahead:abc:1")
      assert Worktree.report_once?(ctx.wt, "ahead:def:1")
    end
  end
end
