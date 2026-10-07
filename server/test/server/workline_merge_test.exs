defmodule Server.Workline.MergeTest do
  # Approving a review lands the workline's branch on main — in the checkout people work in, so only
  # onto main, only clean, never half-done, and history stays linear (the remote takes no merge
  # commits). Real git, temp repos.
  use ExUnit.Case, async: true

  alias Server.Workline.Merge

  setup do
    repo = Path.join(System.tmp_dir!(), "merge-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    git = fn args -> System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    {_, 0} = git.(["init", "-q", "-b", "main"])
    {_, 0} = git.(["config", "user.email", "t@t"])
    {_, 0} = git.(["config", "user.name", "t"])
    File.write!(Path.join(repo, "a.txt"), "one\n")
    {_, 0} = git.(["add", "a.txt"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    {_, 0} = git.(["checkout", "-qb", "work/finder"])
    File.write!(Path.join(repo, "b.txt"), "built\n")
    {_, 0} = git.(["add", "b.txt"])
    {_, 0} = git.(["commit", "-qm", "build"])
    {_, 0} = git.(["checkout", "-q", "main"])
    on_exit(fn -> File.rm_rf!(repo) end)
    %{repo: repo, git: git}
  end

  defp linear?(git), do: match?({"", 0}, git.(["rev-list", "--merges", "HEAD"]))

  test "fast-forwards main to work/<slug>, and says what moved", %{repo: repo, git: git} do
    {before, 0} = git.(["rev-parse", "HEAD"])
    assert {:ok, %{from: from, to: to}} = Merge.merge(repo, "finder")
    assert from == String.trim(before) and to != from
    assert File.read!(Path.join(repo, "b.txt")) == "built\n"
    assert {^to, 0} = then(git.(["rev-parse", "work/finder"]), fn {o, c} -> {String.trim(o), c} end)
    assert linear?(git)
  end

  test "a gate runs on the rebased branch before main moves; red, main stays where it was", %{repo: repo, git: git} do
    File.write!(Path.join(repo, "c.txt"), "meanwhile\n")
    {_, 0} = git.(["add", "c.txt"])
    {_, 0} = git.(["commit", "-qm", "meanwhile on main"])
    {main_before, 0} = git.(["rev-parse", "main"])
    me = self()

    red = fn r, branch ->
      {log, 0} = System.cmd("git", ["-C", r, "log", "--format=%s", branch])
      send(me, {:gated, log})
      {:error, "the gate is red"}
    end

    assert {:error, "the gate is red"} = Merge.merge(repo, "finder", gate: red)
    assert_received {:gated, log}
    assert log =~ "build" and log =~ "meanwhile on main"
    assert {^main_before, 0} = git.(["rev-parse", "main"])

    assert {:ok, _} = Merge.merge(repo, "finder", gate: fn _, _ -> {:ok, :green} end)
    assert File.read!(Path.join(repo, "b.txt")) == "built\n"
  end

  test "main having moved on, the branch is rebased onto it first — still no merge commit", %{repo: repo, git: git} do
    File.write!(Path.join(repo, "c.txt"), "meanwhile\n")
    {_, 0} = git.(["add", "c.txt"])
    {_, 0} = git.(["commit", "-qm", "meanwhile on main"])

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert File.read!(Path.join(repo, "b.txt")) == "built\n" and File.read!(Path.join(repo, "c.txt")) == "meanwhile\n"
    assert linear?(git)
    {subjects, 0} = git.(["log", "--format=%s"])
    assert String.split(subjects, "\n", trim: true) == ["build", "meanwhile on main", "seed"]
  end

  test "a branch checked out in its own worktree is rebased there", %{repo: repo, git: git} do
    wt = repo <> "-wt"
    {_, 0} = git.(["worktree", "add", "-q", wt, "work/finder"])
    on_exit(fn -> File.rm_rf!(wt) end)
    File.write!(Path.join(repo, "c.txt"), "meanwhile\n")
    {_, 0} = git.(["add", "c.txt"])
    {_, 0} = git.(["commit", "-qm", "meanwhile on main"])

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert linear?(git)
    assert File.read!(Path.join(wt, "c.txt")) == "meanwhile\n"
  end

  test "refuses a checkout with uncommitted changes, or one not on main — nothing touched", %{repo: repo, git: git} do
    File.write!(Path.join(repo, "a.txt"), "edited\n")
    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "uncommitted"
    {_, 0} = git.(["checkout", "-q", "a.txt"])

    {_, 0} = git.(["checkout", "-qb", "elsewhere"])
    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "elsewhere"
  end

  test "a conflict is aborted, leaving main and the branch as they were", %{repo: repo, git: git} do
    {_, 0} = git.(["checkout", "-q", "work/finder"])
    File.write!(Path.join(repo, "a.txt"), "theirs\n")
    {_, 0} = git.(["commit", "-qam", "theirs"])
    {_, 0} = git.(["checkout", "-q", "main"])
    File.write!(Path.join(repo, "a.txt"), "ours\n")
    {_, 0} = git.(["commit", "-qam", "ours"])
    {head, 0} = git.(["rev-parse", "HEAD"])
    {tip, 0} = git.(["rev-parse", "work/finder"])

    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "conflict" and why =~ "a.txt"
    refute why =~ "hint:"
    assert {^head, 0} = git.(["rev-parse", "HEAD"])
    assert {^tip, 0} = git.(["rev-parse", "work/finder"])
    assert {"", 0} = git.(["status", "--porcelain"])
  end

  test "a branch that isn't there is refused", %{repo: repo} do
    assert {:error, why} = Merge.merge(repo, "nope")
    assert why =~ "work/nope"
  end

  test "a git step that fails says what git said, not only which step", %{repo: repo, git: git} do
    {_, 0} = git.(["remote", "add", "origin", repo <> "-nowhere.git"])
    assert {:error, why} = Merge.merge(repo, "finder")
    assert why =~ "could not be brought up to date"
    assert why =~ "nowhere.git"
  end

  test "main is brought up to date with its remote first, so a landing builds on what GitHub has", %{
    repo: repo,
    git: git
  } do
    remote = repo <> "-remote.git"
    on_exit(fn -> File.rm_rf!(remote) end)
    {_, 0} = System.cmd("git", ["init", "-q", "--bare", "-b", "main", remote])
    {_, 0} = git.(["remote", "add", "origin", remote])
    {_, 0} = git.(["push", "-q", "-u", "origin", "main"])

    # something lands on GitHub's main that this machine has not pulled
    other = repo <> "-other"
    on_exit(fn -> File.rm_rf!(other) end)
    {_, 0} = System.cmd("git", ["clone", "-q", remote, other])
    File.write!(Path.join(other, "theirs.txt"), "from github\n")

    for args <- [~w(add theirs.txt), ~w(-c user.email=t@t -c user.name=t commit -qm theirs), ~w(push -q origin main)],
        do: {_, 0} = System.cmd("git", ["-C", other | args])

    assert {:ok, _} = Merge.merge(repo, "finder")
    assert File.read!(Path.join(repo, "theirs.txt")) == "from github\n"
    assert File.read!(Path.join(repo, "b.txt")) == "built\n"
  end
end
