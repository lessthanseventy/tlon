defmodule Console.SessionsTest do
  @moduledoc "The session registry — one embedded terminal per thread, dropped when it exits."
  # The registry is a shared named process (started by the app), so run serially.
  use ExUnit.Case, async: false

  alias Console.Sessions

  test "ensure starts one terminal per thread, is idempotent, and drops it when it exits" do
    {:ok, pid} = Sessions.ensure(9101, cmd: "/bin/cat", cols: 40, rows: 4)
    assert is_pid(pid)
    assert Sessions.terminal(9101) == pid

    # idempotent — the same thread returns the same terminal
    assert {:ok, ^pid} = Sessions.ensure(9101, cmd: "/bin/cat")

    # a different thread gets its own terminal
    {:ok, other} = Sessions.ensure(9102, cmd: "/bin/cat", cols: 40, rows: 4)
    assert other != pid
    on_exit(fn -> if Process.alive?(other), do: GenServer.stop(other) end)

    # when a terminal exits, the registry no longer hands it out (no stale row)
    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    # let the registry process its own DOWN
    Process.sleep(50)
    assert Sessions.terminal(9101) == nil
  end
end
