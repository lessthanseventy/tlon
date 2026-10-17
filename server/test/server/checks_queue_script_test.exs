defmodule Server.ChecksQueueScriptTest do
  # scripts/checks-queue.sh: a shell that can't open the queue's lock is refused, not run beside the
  # merge queue's gates.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/checks-queue.sh", __DIR__)

  defp queue(env) do
    env = [{"XDG_RUNTIME_DIR", "/nonexistent/tlon-test-runtime"} | env]
    System.cmd("bash", [@script, "echo", "ran"], env: env, stderr_to_stdout: true)
  end

  test "an unopenable lock exits 2 without running the command" do
    assert {out, 2} = queue([])
    assert out =~ "run the check unsandboxed"
    refute out =~ "ran\n"
  end

  test "CHECKS_UNQUEUED=1 runs the command unqueued" do
    assert {out, 0} = queue([{"CHECKS_UNQUEUED", "1"}])
    assert out =~ "running unqueued"
    assert out =~ "ran\n"
  end
end
