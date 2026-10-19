defmodule Server.RunFromRootTest do
  # scripts/run-from-root.sh: `release:smoke` launched in a worktree on an old base runs the shared
  # root checkout's copy of the script, not the worktree's own old one.
  use ExUnit.Case, async: true

  @scripts Path.expand("../../../scripts", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "run-from-root-#{System.pid()}-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    root = Path.join(tmp, "tlon")
    File.mkdir_p!(tmp)
    sh!(tmp, "git init -q -b main tlon")
    File.mkdir_p!(Path.join(root, "scripts"))
    File.write!(Path.join(root, "scripts/release-smoke.sh"), "echo old-script \"$@\"\n")
    File.cp!(Path.join(@scripts, "run-from-root.sh"), Path.join(root, "scripts/run-from-root.sh"))

    sh!(root, """
    git config user.email t@t && git config user.name t && git add -A && git commit -qm one &&
    git worktree add -q ../seat -b seat &&
    echo 'echo new-script "$@"' >scripts/release-smoke.sh && chmod +x scripts/release-smoke.sh && git commit -qam two
    """)

    %{root: root, seat: Path.join(tmp, "seat")}
  end

  defp sh!(cwd, cmd) do
    {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
    out
  end

  test "a worktree on an old base runs the root checkout's script, with the arguments", ctx do
    assert File.read!(Path.join(ctx.seat, "scripts/release-smoke.sh")) =~ "old-script"

    assert {out, 0} =
             System.cmd("bash", [Path.join(ctx.seat, "scripts/run-from-root.sh"), "release-smoke.sh", "work/x"],
               stderr_to_stdout: true
             )

    assert out == "new-script work/x\n"
  end
end
