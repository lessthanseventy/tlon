defmodule Server.Workline.MergeTest do
  # Approving a review merges the workline's branch into main — in the checkout people work in, so
  # only onto main, only clean, never half-merged. Real git, temp repos.
  use ExUnit.Case, async: true

  alias Server.Workline.Merge

  setup do
    repo = Path.join(System.tmp_dir!(), "merge-test-#{System.unique_integer([:positive])}")
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

  test "merges work/<slug> into main with a merge commit, and says what moved", %{repo: repo, git: git} do
    {before, 0} = git.(["rev-parse", "HEAD"])
    assert {:ok, %{from: from, to: to}} = Merge.merge(repo, "finder", "the finder finds tickets")
    assert from == String.trim(before) and to != from
    assert File.read!(Path.join(repo, "b.txt")) == "built\n"
    {parents, 0} = git.(["rev-list", "--parents", "-n", "1", "HEAD"])
    assert length(String.split(parents)) == 3
    {msg, 0} = git.(["log", "-1", "--format=%s"])
    assert msg =~ "work/finder" and msg =~ "the finder finds tickets"
  end

  test "refuses a checkout with uncommitted changes, or one not on main — nothing touched", %{repo: repo, git: git} do
    File.write!(Path.join(repo, "a.txt"), "edited\n")
    assert {:error, why} = Merge.merge(repo, "finder", "t")
    assert why =~ "uncommitted"
    {_, 0} = git.(["checkout", "-q", "a.txt"])

    {_, 0} = git.(["checkout", "-qb", "elsewhere"])
    assert {:error, why} = Merge.merge(repo, "finder", "t")
    assert why =~ "elsewhere"
  end

  test "a conflict is aborted, leaving main as it was", %{repo: repo, git: git} do
    {_, 0} = git.(["checkout", "-q", "work/finder"])
    File.write!(Path.join(repo, "a.txt"), "theirs\n")
    {_, 0} = git.(["commit", "-qam", "theirs"])
    {_, 0} = git.(["checkout", "-q", "main"])
    File.write!(Path.join(repo, "a.txt"), "ours\n")
    {_, 0} = git.(["commit", "-qam", "ours"])
    {head, 0} = git.(["rev-parse", "HEAD"])

    assert {:error, why} = Merge.merge(repo, "finder", "t")
    assert why =~ "conflict"
    assert {^head, 0} = git.(["rev-parse", "HEAD"])
    assert {"", 0} = git.(["status", "--porcelain"])
  end

  test "a branch that isn't there is refused", %{repo: repo} do
    assert {:error, why} = Merge.merge(repo, "nope", "t")
    assert why =~ "work/nope"
  end
end
