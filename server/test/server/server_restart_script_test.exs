defmodule Server.ServerRestartScriptTest do
  # scripts/server-restart.sh, server:restart's door: it restarts only when that cuts nothing off.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/server-restart.sh", __DIR__)

  setup do
    dir = Path.join(System.tmp_dir!(), "restart-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    # systemctl stand-in: records that a restart happened
    File.write!(Path.join(dir, "systemctl"), "#!/bin/sh\necho \"systemctl $*\" >> #{dir}/ran\n")
    File.chmod!(Path.join(dir, "systemctl"), 0o755)
    %{dir: dir}
  end

  defp run(dir, quiet_says, args \\ []) do
    cli = Path.join(dir, "cli")
    announce = ~s(if [ "$1" = announce-restart ]; then echo "cli $*" >> #{dir}/ran; exit 0; fi)
    File.write!(cli, "#!/bin/sh\n#{announce}\n#{quiet_says}\n")
    File.chmod!(cli, 0o755)
    env = [{"TLON_CLI", cli}, {"PATH", "#{dir}:#{System.get_env("PATH")}"}]
    {out, code} = System.cmd("bash", [@script | args], env: env, stderr_to_stdout: true)
    {out, code, File.read(Path.join(dir, "ran"))}
  end

  test "quiet: it restarts", %{dir: dir} do
    assert {_, 0, {:ok, ran}} = run(dir, "echo quiet")
    assert ran =~ "systemctl --user restart tlon"
  end

  test "the workers hear it first: the cli announces the restart, then it restarts", %{dir: dir} do
    assert {_, 0, {:ok, ran}} = run(dir, "echo quiet")
    assert [announce, restart | _status] = String.split(ran, "\n", trim: true)
    assert announce == "cli announce-restart the operator ran server:restart"
    assert restart =~ "restart tlon"
  end

  test "busy: it refuses, saying what a restart would cut off, and restarts nothing", %{dir: dir} do
    assert {out, 1, {:error, :enoent}} = run(dir, "echo busy; echo 'the verify of #140 is running'")
    assert out =~ "the verify of #140 is running"
    assert out =~ "--force"
  end

  test "busy with --force: it restarts anyway", %{dir: dir} do
    assert {_, 0, {:ok, ran}} = run(dir, "echo busy; echo 'the verify of #140 is running'", ["--force"])
    assert ran =~ "restart tlon"
  end

  test "a server that can't be asked (down) is restarted — that is what down needs", %{dir: dir} do
    assert {_, 0, {:ok, _}} = run(dir, "echo 'noconnection' >&2; exit 1")
  end
end
