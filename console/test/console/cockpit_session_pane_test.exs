defmodule Console.CockpitSessionPaneTest do
  @moduledoc """
  The cockpit's SESSION-pane seams: the pane's PTY belongs to the OPEN thread, so moving the centre
  off a thread ends it. Drives the live `Console.Sessions` registry (a shared named process), so
  not async.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit
  alias Console.Sessions

  @a {:session, 9201}
  @b {:session, 9202}

  setup do
    on_exit(fn ->
      for key <- [@a, @b], do: Sessions.close(key)
    end)
  end

  test "opening a different thread ends the previous thread's pane PTY" do
    {:ok, pid} = Sessions.ensure(@a, cmd: "/bin/cat", cols: 20, rows: 4)
    ref = Process.monitor(pid)

    assert Cockpit.drop_stale_session(%{opened_thread: 9201}, 9202) == :ok
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    assert Sessions.terminal(@a) == nil
  end

  test "re-opening the SAME thread keeps its PTY — the pane doesn't restart under you" do
    {:ok, pid} = Sessions.ensure(@a, cmd: "/bin/cat", cols: 20, rows: 4)

    assert Cockpit.drop_stale_session(%{opened_thread: 9201}, 9201) == :ok
    assert Sessions.terminal(@a) == pid
  end

  test "closing the conversation (no next thread) ends the pane too" do
    {:ok, _pid} = Sessions.ensure(@b, cmd: "/bin/cat", cols: 20, rows: 4)

    assert Cockpit.drop_stale_session(%{opened_thread: 9202}, nil) == :ok
    assert Sessions.terminal(@b) == nil
  end

  test "nothing open: nothing to drop" do
    assert Cockpit.drop_stale_session(%{opened_thread: nil}, 9201) == :ok
  end
end
