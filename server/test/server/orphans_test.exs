defmodule Server.OrphansTest do
  # One seat, one session: a process still holding a seat's identity (TLON_AUTHOR + TLON_THREAD)
  # with no window left is an earlier session of that handle — retired before a respawn takes the
  # seat, so two never take wakes at once.
  use ExUnit.Case, async: true

  alias Server.Orphans

  setup do
    proc = Path.join(System.tmp_dir!(), "orphans-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(proc)
    on_exit(fn -> File.rm_rf!(proc) end)
    %{proc: proc}
  end

  defp process(proc, pid, env) do
    dir = Path.join(proc, Integer.to_string(pid))
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "environ"), Enum.map_join(env, &(&1 <> <<0>>)))
  end

  test "finds processes holding the seat's identity, and only those", %{proc: proc} do
    process(proc, 101, ["HOME=/x", "TLON_THREAD=257", "TLON_AUTHOR=emma"])
    process(proc, 102, ["TLON_THREAD=257", "TLON_AUTHOR=lonnrot"])
    process(proc, 103, ["TLON_THREAD=255", "TLON_AUTHOR=emma"])
    process(proc, 104, ["HOME=/x"])
    File.mkdir_p!(Path.join(proc, "self"))

    assert Orphans.holders(257, "emma", proc_dir: proc) == [101]
  end

  test "retire/3 signals each holder and says how many", %{proc: proc} do
    process(proc, 101, ["TLON_THREAD=257", "TLON_AUTHOR=emma"])
    process(proc, 105, ["TLON_THREAD=257", "TLON_AUTHOR=emma"])
    test = self()

    opts = [proc_dir: proc, kill: fn pid -> send(test, {:killed, pid}) end, grace: 0, force: fn _ -> :ok end]

    assert Orphans.retire(257, "emma", [notify: fn _ -> :ok end] ++ opts) == 2
    assert_received {:killed, 101}
    assert_received {:killed, 105}
  end

  test "a holder that ignores SIGTERM is SIGKILLed after the grace, and the thread is told", %{proc: proc} do
    process(proc, 101, ["TLON_THREAD=257", "TLON_AUTHOR=emma"])
    process(proc, 105, ["TLON_THREAD=257", "TLON_AUTHOR=emma"])
    test = self()

    opts = [
      proc_dir: proc,
      grace: 0,
      kill: fn pid -> if pid == 101, do: File.rm_rf!(Path.join(proc, "101")) end,
      force: fn pid -> send(test, {:forced, pid}) end,
      notify: fn text -> send(test, {:notice, text}) end
    ]

    assert Orphans.retire(257, "emma", opts) == 2
    assert_received {:forced, 105}
    refute_received {:forced, 101}
    assert_received {:notice, text}
    assert text =~ "retired 2" and text =~ "SIGKILL" and text =~ "105"
  end

  test "holders that let go within the grace are never SIGKILLed, and no seat held means no notice", %{proc: proc} do
    process(proc, 101, ["TLON_THREAD=257", "TLON_AUTHOR=emma"])
    test = self()

    opts = [
      proc_dir: proc,
      kill: fn pid -> File.rm_rf!(Path.join(proc, "#{pid}")) end,
      force: fn pid -> send(test, {:forced, pid}) end,
      notify: fn text -> send(test, {:notice, text}) end
    ]

    assert Orphans.retire(257, "emma", opts) == 1
    refute_received {:forced, _}
    assert_received {:notice, text}
    refute text =~ "SIGKILL"

    assert Orphans.retire(257, "emma", opts) == 0
    refute_received {:notice, _}
  end

  test "never signals the caller's own process", %{proc: proc} do
    process(proc, List.to_integer(:os.getpid()), ["TLON_THREAD=257", "TLON_AUTHOR=emma"])

    assert Orphans.retire(257, "emma", proc_dir: proc, kill: fn _ -> flunk("signalled self") end, notify: &flunk/1) == 0
  end
end
