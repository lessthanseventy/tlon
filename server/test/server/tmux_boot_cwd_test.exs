defmodule Server.TmuxBootCwdTest do
  # A seat boots in its worktree or not at all (#336, #522): a pane whose cd failed ran its harness in
  # $HOME, and Claude Code then mounted every repo under home into its sandbox, past bwrap's 9000
  # arguments, so every Bash call in that seat died.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp boot(env, start) do
    System.cmd("sh", ["-c", Server.Tmux.cd_worktree() <> "\npwd"], env: env, cd: start, stderr_to_stdout: true)
  end

  setup %{tmp_dir: tmp} do
    home = Path.join(tmp, "home")
    run = Path.join(tmp, "run")
    wt = Path.join(tmp, "wt")
    for d <- [home, run, wt], do: File.mkdir_p!(d)
    {_, 0} = System.cmd("git", ["init", "-q"], cd: wt)
    %{home: home, run: run, wt: wt, tmp: tmp}
  end

  test "into its worktree", ctx do
    assert {out, 0} = boot([{"TLON_CWD", ctx.wt}, {"HOME", ctx.home}], ctx.home)
    assert String.trim(out) == ctx.wt
  end

  test "a worktree that is gone: refused, never left in $HOME", ctx do
    assert {out, 1} = boot([{"TLON_CWD", Path.join(ctx.tmp, "gone")}, {"HOME", ctx.home}], ctx.home)
    assert out =~ "refusing"
    refute out =~ ctx.home <> "\n"
  end

  test "a worktree dir with no .git (a half-made one): refused", ctx do
    bare = Path.join(ctx.tmp, "bare")
    File.mkdir_p!(bare)
    assert {out, 1} = boot([{"TLON_CWD", bare}, {"HOME", ctx.home}], ctx.home)
    assert out =~ "refusing"
  end

  test "no worktree at all (a thread with no repo): its runtime dir, not $HOME", ctx do
    assert {out, 0} = boot([{"TLON_CWD", nil}, {"HOME", ctx.home}, {"XDG_RUNTIME_DIR", ctx.run}], ctx.home)
    assert String.trim(out) == ctx.run
  end
end
