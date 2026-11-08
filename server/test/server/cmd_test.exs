defmodule Server.CmdTest do
  # A shell-out that hangs ends at its wall with exit 124 and says so; one that answers is untouched.
  use ExUnit.Case, async: true

  alias Server.Cmd
  alias Server.Git

  test "a command past its timeout is cut off, exit 124, within the bound" do
    {us, {out, 124}} = :timer.tc(fn -> Cmd.run("sleep", ["30"], timeout: 1) end)
    assert us < 8_000_000
    assert out =~ "sleep 30 timed out after 1 s"
  end

  test "a command that answers in time is System.cmd's answer" do
    assert {"hi\n", 0} = Cmd.run("echo", ["hi"])
    assert {_, 3} = Cmd.run("sh", ["-c", "exit 3"], timeout: 5)
    assert {_, 127} = Cmd.run("no-such-command-here", [])
  end

  test ":infinity runs unbounded, and opts pass through" do
    assert {"a\n", 0} = Cmd.run("sh", ["-c", "echo $X"], env: [{"X", "a"}], timeout: :infinity)
    assert {"/\n", 0} = Cmd.run("pwd", [], cd: "/")
  end

  test "Git.cmd and Git.run are git -C repo, stderr in the answer" do
    repo = Path.join(System.tmp_dir!(), "cmd-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)
    {_, 0} = Cmd.run("git", ["init", "-q", repo])

    assert {:ok, ".git"} = Git.run(repo, ["rev-parse", "--git-dir"])
    assert {:error, out} = Git.run(repo, ["rev-parse", "--verify", "-q", "nope"])
    assert out == ""
    assert {out, code} = Git.cmd(repo, ["no-such-verb"])
    assert code != 0 and out =~ "no-such-verb"
  end
end
