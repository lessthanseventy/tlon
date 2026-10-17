defmodule Server.FreshScriptTest do
  # scripts/lib/fresh-script.sh: a machine-wide script run from a checkout whose copy origin/main has
  # since changed is refused. Real git; the script under test is checks-queue.sh.
  use ExUnit.Case, async: true

  @scripts Path.expand("../../../scripts", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "fresh-script-#{System.pid()}-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    root = Path.join(tmp, "tlon")
    File.mkdir_p!(tmp)
    sh!(tmp, "git init -q --bare origin.git && git clone -q origin.git tlon")
    File.mkdir_p!(Path.join(root, "scripts/lib"))

    for f <- ~w(checks-queue.sh lib/fresh-script.sh),
        do: File.cp!(Path.join(@scripts, f), Path.join(root, "scripts/#{f}"))

    sh!(root, """
    git config user.email t@t && git config user.name t && git add -A && git commit -qm one &&
    git branch -M main && git push -q origin main && git branch old &&
    echo '# main moved' >>scripts/checks-queue.sh && git commit -qam two && git push -q origin main
    """)

    %{tmp: tmp, root: root}
  end

  defp sh!(cwd, cmd) do
    {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
    out
  end

  defp queue(ctx, env \\ []) do
    env = [{"XDG_RUNTIME_DIR", ctx.tmp} | env]
    System.cmd("bash", [Path.join(ctx.root, "scripts/checks-queue.sh"), "echo", "ran"], env: env, stderr_to_stdout: true)
  end

  test "a checkout up to date with main runs the script", ctx do
    assert {out, 0} = queue(ctx)
    assert out =~ "ran"
  end

  test "a checkout branched before main changed the script is refused, naming the rebase", ctx do
    sh!(ctx.root, "git checkout -q old")
    assert {out, 2} = queue(ctx)
    assert out =~ "behind origin/main's"
    assert out =~ "rebase onto origin/main"
    refute out =~ "ran\n"
  end

  test "a rebased checkout with edits of its own to the script runs it", ctx do
    sh!(ctx.root, "git checkout -q old && sed -i '2i # mine' scripts/checks-queue.sh && git commit -qam mine")
    sh!(ctx.root, "git rebase -q origin/main")
    assert {_, 0} = queue(ctx)
  end

  test "TLON_STALE_SCRIPTS_OK=1 runs a stale copy anyway", ctx do
    sh!(ctx.root, "git checkout -q old")
    assert {out, 0} = queue(ctx, [{"TLON_STALE_SCRIPTS_OK", "1"}])
    assert out =~ "ran"
  end
end
