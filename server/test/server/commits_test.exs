defmodule Server.CommitsTest do
  # The commit ↔ thread join: a `Tlon-Thread: <id>` trailer, stamped by scripts/git-hooks/
  # prepare-commit-msg from TLON_THREAD, read back by `git log --grep`; and the branch FENCE
  # (pre-commit): a pane with TLON_THREAD commits only on work/*. Real git, temp repos, the real
  # hooks (core.hooksPath → scripts/git-hooks), so the write side is tested too. The fixture sits
  # on `work/fixture`, where a coworker's commits are allowed.
  use ExUnit.Case, async: false

  alias Server.Commits

  @hooks Path.expand("../../../scripts/git-hooks", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "commits-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    git = fn args, env -> System.cmd("git", ["-C", tmp | args], stderr_to_stdout: true, env: env) end
    {_, 0} = git.(["init", "-q", "-b", "main"], [])
    {_, 0} = git.(["config", "user.email", "test@test"], [])
    {_, 0} = git.(["config", "user.name", "test"], [])
    {_, 0} = git.(["config", "core.hooksPath", @hooks], [])

    # A commit touching `file`, made from a pane with (or without) a thread identity.
    commit = fn file, msg, env ->
      File.write!(Path.join(tmp, file), "#{file}\n")
      {_, 0} = git.(["add", file], [])
      {_, 0} = git.(["commit", "-qm", msg], env)
    end

    commit.("seed", "seed", [])
    {_, 0} = git.(["checkout", "-qb", "work/fixture"], [])

    on_exit(fn -> File.rm_rf!(tmp) end)
    %{repo: tmp, git: git, commit: commit}
  end

  test "the hook stamps Tlon-Thread/Tlon-Author from the pane's env; a plain terminal gets none",
       %{repo: repo, git: git, commit: commit} do
    commit.("a", "thread work", [{"TLON_THREAD", "42"}, {"TLON_AUTHOR", "hronir"}])
    {body, 0} = git.(["log", "-1", "--format=%B"], [])
    assert body =~ "Tlon-Thread: 42\n"
    assert body =~ "Tlon-Author: hronir\n"

    commit.("b", "human work", [])
    {body, 0} = git.(["log", "-1", "--format=%B"], [])
    refute body =~ "Tlon-"

    assert {:ok, [%{subject: "thread work", author: "test", sha: sha, at: at}]} = Commits.list(repo, 42)
    assert String.length(sha) == 40
    assert at =~ ~r/^\d{4}-\d{2}-\d{2}T/
  end

  test "another thread's commits, and an unrelated trailer, do not match", %{repo: repo, commit: commit} do
    commit.("a", "mine", [{"TLON_THREAD", "7"}])
    commit.("b", "theirs", [{"TLON_THREAD", "70"}])
    commit.("c", "handwritten\n\nTlon-Thread: 7x", [])
    assert {:ok, [%{subject: "mine"}]} = Commits.list(repo, 7)
  end

  test "the join survives an amend and a rebase onto another branch", %{repo: repo, git: git, commit: commit} do
    {_, 0} = git.(["checkout", "-qb", "work/t9"], [])
    commit.("a", "on the branch", [{"TLON_THREAD", "9"}])
    {_, 0} = git.(["commit", "-q", "--amend", "-m", "on the branch, amended"], [{"TLON_THREAD", "9"}])
    {_, 0} = git.(["checkout", "-q", "main"], [])
    commit.("b", "main moved", [])
    {_, 0} = git.(["rebase", "-q", "main", "work/t9"], [])
    assert {:ok, [%{subject: "on the branch, amended"}]} = Commits.list(repo, 9)
  end

  test "branch fencing: a pane with TLON_THREAD commits only on work/*; a human terminal anywhere", %{
    repo: repo,
    git: git
  } do
    {_, 0} = git.(["checkout", "-q", "main"], [])
    File.write!(Path.join(repo, "a"), "a\n")
    {_, 0} = git.(["add", "a"], [])
    {out, code} = git.(["commit", "-qm", "on main from a pane"], [{"TLON_THREAD", "3"}])
    assert code != 0
    assert out =~ "refusing to commit"
    # the same commit from a human terminal lands
    {_, 0} = git.(["commit", "-qm", "on main from a human"], [])
    # and the pane commits fine on its own work/ branch
    {_, 0} = git.(["checkout", "-qb", "work/t3"], [])
    File.write!(Path.join(repo, "b"), "b\n")
    {_, 0} = git.(["add", "b"], [])
    {_, 0} = git.(["commit", "-qm", "on the branch"], [{"TLON_THREAD", "3"}])
    assert {:ok, [%{subject: "on the branch"}]} = Commits.list(repo, 3)
  end

  test "an unreadable repo is an error, and for_thread turns no-repo into an empty section", %{repo: repo} do
    assert {:error, _} = Commits.list(Path.join(repo, "nope"), 1)
    assert Commits.for_thread(%Server.Thread{id: 1}) == %{shown: [], more: 0}
  end
end
