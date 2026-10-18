defmodule Server.CheckMainScriptTest do
  # scripts/check-main.sh: the gate on origin/main in a throwaway worktree, which a TERM (a service
  # stop) must not leave behind. Real git; mise and mix stubbed.
  use ExUnit.Case, async: true

  @scripts Path.expand("../../../scripts", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "check-main-#{System.pid()}-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp) end)
    root = Path.join(tmp, "tlon")
    bin = Path.join(tmp, "bin")
    scratch = Path.join(tmp, "scratch")
    File.mkdir_p!(bin)
    File.mkdir_p!(scratch)

    # `mise run check` waits to be killed; every other mise call succeeds
    stub(bin, "mise", ~S(if [ "$1" = run ]; then touch "$SCRATCH/gating"; exec sleep 60; fi))
    stub(bin, "mix", "exit 0")

    sh!(tmp, "git init -q --bare origin.git && git clone -q origin.git tlon")
    File.mkdir_p!(Path.join(root, "scripts/lib"))
    File.mkdir_p!(Path.join(root, "server"))
    File.write!(Path.join(root, "server/mix.exs"), "")

    for f <- ~w(check-main.sh git-fetch-origin.sh lib/seed-hex.sh),
        do: File.cp!(Path.join(@scripts, f), Path.join(root, "scripts/#{f}"))

    sh!(root, """
    git config user.email t@t && git config user.name t &&
    git add -A && git commit -qm one && git branch -M main && git push -q origin main
    """)

    %{tmp: tmp, root: root, bin: bin, scratch: scratch}
  end

  defp stub(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
  end

  defp sh!(cwd, cmd) do
    {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
    out
  end

  defp wait_for(path, tries \\ 200) do
    cond do
      File.exists?(path) -> :ok
      tries == 0 -> flunk("#{path} never appeared")
      true -> Process.sleep(100) && wait_for(path, tries - 1)
    end
  end

  defp env(ctx) do
    [{"PATH", ctx.bin <> ":" <> System.get_env("PATH")}, {"TMPDIR", ctx.scratch}, {"SCRATCH", ctx.scratch}]
  end

  defp start(ctx) do
    Port.open({:spawn_executable, System.find_executable("bash")}, [
      :exit_status,
      args: [Path.join(ctx.root, "scripts/check-main.sh")],
      env: Enum.map(env(ctx), fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
      cd: String.to_charlist(ctx.root)
    ])
  end

  # a service stop signals the whole tree: the script and the gate it waits on
  defp stop(port) do
    {:os_pid, pid} = Port.info(port, :os_pid)
    System.cmd("pkill", ["-TERM", "-P", "#{pid}"])
    System.cmd("kill", ["-TERM", "#{pid}"])
  end

  defp leftovers(ctx), do: Path.wildcard(Path.join(ctx.scratch, "tlon-main-*"))

  test "a TERM mid-gate removes the worktree and the log", ctx do
    port = start(ctx)

    wait_for(Path.join(ctx.scratch, "gating"))
    assert length(leftovers(ctx)) == 2

    stop(port)

    assert_receive {^port, {:exit_status, 143}}, 10_000
    assert leftovers(ctx) == []
    refute sh!(ctx.root, "git worktree list") =~ "tlon-main-"
  end

  test "a run sweeps the worktree and log a SIGKILLed one left", ctx do
    stale = Path.join(ctx.scratch, "tlon-main-STALE1")
    sh!(ctx.root, "git worktree add -q --detach #{stale} HEAD")
    File.write!(Path.join(ctx.scratch, "tlon-main-check-STALE2"), "old")
    sh!(ctx.scratch, "touch -d '3 hours ago' tlon-main-STALE1 tlon-main-check-STALE2")

    port = start(ctx)

    wait_for(Path.join(ctx.scratch, "gating"))
    refute File.exists?(stale)
    refute File.exists?(Path.join(ctx.scratch, "tlon-main-check-STALE2"))
    stop(port)
    assert_receive {^port, {:exit_status, 143}}, 10_000
  end
end
