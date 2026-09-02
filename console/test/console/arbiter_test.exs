defmodule Console.ArbiterTest do
  @moduledoc "The aleph hub's arbiter backend — funes' wake actuated against embedded terminals."
  use ExUnit.Case, async: false

  alias Console.Arbiter
  alias Console.Sessions
  alias Console.Terminal

  test "sanitize collapses a prompt to one clean line" do
    assert Arbiter.sanitize("first\nsecond\ttab   run") == "first second tab run"
  end

  test "thread_id parses TLON_THREAD from an exports block, else nil" do
    assert Arbiter.thread_id(~s(export TLON_MCP_URL="x"\nexport TLON_THREAD="42")) == 42
    assert Arbiter.thread_id("no thread here") == nil
  end

  test "wake with no live terminal for the thread is {:error, :no_terminal}, never a crash" do
    assert Arbiter.wake(%{thread_id: 999_999}, "hi") == {:error, :no_terminal}
  end

  test "wake degrades to {:error, :no_terminal} when Sessions is down, never a crash" do
    # Reproduces the hub crash: a pi→claude wake actuated through the switchboard while
    # Console.Sessions is wedged/torn-down. The raw GenServer.call exits (:noproc / :timeout),
    # which used to propagate up and kill the hub — the ISSUES line
    # `GenServer.call(Console.Sessions, {:terminal, :machine}, 5000)`.
    Supervisor.terminate_child(Console.Supervisor, Sessions)
    on_exit(fn -> Supervisor.restart_child(Console.Supervisor, Sessions) end)

    assert Arbiter.wake(%{thread_id: 8802}, "hi") == {:error, :no_terminal}
  end

  test "spawn degrades to {:error, :sessions_down} when Sessions is down, never a crash" do
    exports = ~s(export TLON_THREAD="8803")
    Supervisor.terminate_child(Console.Supervisor, Sessions)
    on_exit(fn -> Supervisor.restart_child(Console.Supervisor, Sessions) end)

    assert Arbiter.spawn(exports) == {:error, :sessions_down}
  end

  test "wake writes the sanitized prompt + Enter into the thread's terminal" do
    # cat echoes stdin, so a wake that reaches the PTY reappears on the screen.
    {:ok, term} = Sessions.ensure(8801, cmd: "/bin/cat", cols: 40, rows: 4)
    on_exit(fn -> if Process.alive?(term), do: GenServer.stop(term) end)

    assert :ok = Arbiter.wake(%{thread_id: 8801}, "wake up")
    Process.sleep(120)

    text = term |> Terminal.cells() |> List.flatten() |> Enum.map_join(fn {g, _, _, _} -> g end)
    assert text =~ "wake up"
  end
end
