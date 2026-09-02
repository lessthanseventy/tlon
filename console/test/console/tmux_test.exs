defmodule Console.TmuxTest do
  @moduledoc """
  The tmux naming contract every coworker window rides — id-derived per workspace, so a rename can't
  orphan a session — and the `run/3` seam the whole cockpit (and `Console.Crew`, with its own runner)
  goes through. Pinned here because nothing else in the suite asserts the names themselves.
  """
  use ExUnit.Case, async: false

  alias Console.Tmux

  describe "naming: id-derived, rename-proof" do
    test "session is w<id>, socket is console-workspace-<id>" do
      assert Tmux.session(7) == "w7"
      assert Tmux.socket(7) == "console-workspace-7"
    end

    test "target is session:window — index, name, or =name for an exact match" do
      assert Tmux.target(7, 3) == "w7:3"
      assert Tmux.target(7, "=builder-fix") == "w7:=builder-fix"
    end

    test "argv prefixes -L <socket> so no call can land on the operator's own tmux server" do
      assert Tmux.argv(7, ["has-session", "-t", "w7"]) == ["-L", "console-workspace-7", "has-session", "-t", "w7"]
    end
  end

  describe "run/3: the command seam" do
    setup do
      test_pid = self()

      Application.put_env(:console, :tlon_cmd, fn "tmux", args, opts ->
        send(test_pid, {:tmux, args, opts})
        {"out", 0}
      end)

      on_exit(fn -> Application.delete_env(:console, :tlon_cmd) end)
    end

    test "routes through :tlon_cmd with -L and stderr folded in" do
      assert {"out", 0} = Tmux.run(7, ["display", "-p", "x"])
      assert_receive {:tmux, ["-L", "console-workspace-7", "display", "-p", "x"], [stderr_to_stdout: true]}
    end

    test "a nil workspace (server down) is a no-op miss, never a call without -L" do
      assert {_out, 1} = Tmux.run(nil, ["kill-server"])
      refute_receive {:tmux, _, _}, 20
    end

    test "a per-call runner overrides the seam (Console.Crew's own :crew_cmd)" do
      test_pid = self()

      runner = fn "tmux", args, _opts ->
        send(test_pid, {:crew, args})
        {"", 0}
      end

      Tmux.submit(1, "r42", runner: runner)
      assert_receive {:crew, ["-L", "console-workspace-1", "send-keys", "-t", "w1:r42", "Enter"]}
      refute_receive {:tmux, _, _}, 20
    end

    test "send_text types literally (-l) and submit sends Enter as a separate call — the two-phase inject" do
      Tmux.send_text(7, 2, "hello there")
      Tmux.submit(7, 2)
      assert_receive {:tmux, ["-L", _, "send-keys", "-l", "-t", "w7:2", "hello there"], _}
      assert_receive {:tmux, ["-L", _, "send-keys", "-t", "w7:2", "Enter"], _}
    end

    test "kill/select/set_window_option target session:window" do
      Tmux.kill_window(7, 3)
      Tmux.select_window(7, "borges")
      Tmux.set_window_option(7, "=planner-x", "@funes_thread", "9")
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", "w7:3"], _}
      assert_receive {:tmux, ["-L", _, "select-window", "-t", "w7:borges"], _}
      assert_receive {:tmux, ["-L", _, "set-option", "-w", "-t", "w7:=planner-x", "@funes_thread", "9"], _}
    end

    test "list_windows asks for the tab format and parses it; a nonzero exit is an empty strip" do
      Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
        if "list-windows" in args, do: {"1\t0\ttertius\t\t\t\n", 0}, else: {"", 1}
      end)

      assert [%{name: "tertius", active?: true, index: "0"}] = Tmux.list_windows(7)

      Application.put_env(:console, :tlon_cmd, fn "tmux", _args, _opts -> {"no server", 1} end)
      assert Tmux.list_windows(7) == []
    end
  end

  describe "tab lookups" do
    @tabs [
      %{name: "tertius", active?: true, index: "0", thread_id: nil, opening: nil, activity: nil},
      %{name: "builder-fix", active?: false, index: "1", thread_id: 7, opening: "done", activity: nil},
      %{name: "t9", active?: false, index: "2", thread_id: nil, opening: nil, activity: nil}
    ]

    test "window_index finds a window by name" do
      assert Tmux.window_index(@tabs, "builder-fix") == "1"
      assert Tmux.window_index(@tabs, "nope") == nil
    end

    test "leaf_tab resolves thread → window by the @funes_thread tag, else the legacy t<id> name" do
      assert %{index: "1"} = Tmux.leaf_tab(@tabs, 7)
      assert %{index: "2"} = Tmux.leaf_tab(@tabs, 9)
      assert Tmux.leaf_tab(@tabs, 8) == nil
    end

    test "leaf_window? is the tag or the t<id> name — never the center/tail windows" do
      assert Enum.map(@tabs, &Tmux.leaf_window?/1) == [false, true, true]
    end
  end

  describe "parse_windows/1: the workspace's windows as tab data" do
    test "each `<active>\\t<index>\\t<name>\\t<@funes_thread>\\t<@funes_opening>\\t<activity>` line becomes a tab" do
      out = "1\t1\tpi\t\t\t\n0\t2\tclaude\t\t\t\n0\t3\treviewer-fix-the-bug\t7\tdone\t1755900000\n"

      assert Tmux.parse_windows(out) == [
               %{name: "pi", active?: true, index: "1", thread_id: nil, opening: nil, activity: nil},
               %{name: "claude", active?: false, index: "2", thread_id: nil, opening: nil, activity: nil},
               %{
                 name: "reviewer-fix-the-bug",
                 active?: false,
                 index: "3",
                 thread_id: 7,
                 opening: "done",
                 activity: 1_755_900_000
               }
             ]
    end

    test "shorter lines (no thread/opening/activity tags) still parse — missing fields nil" do
      assert Tmux.parse_windows("1\t1\tpi\n") ==
               [%{name: "pi", active?: true, index: "1", thread_id: nil, opening: nil, activity: nil}]

      assert Tmux.parse_windows("0\t4\tplanner-x\t9\n") ==
               [%{name: "planner-x", active?: false, index: "4", thread_id: 9, opening: nil, activity: nil}]

      assert Tmux.parse_windows("0\t4\tplanner-x\t9\tdone\n") ==
               [%{name: "planner-x", active?: false, index: "4", thread_id: 9, opening: "done", activity: nil}]
    end

    test "empty output (session not up yet) is an empty strip, not a crash" do
      assert Tmux.parse_windows("") == []
    end

    test "a malformed line is dropped, not guessed" do
      assert Tmux.parse_windows("garbage\n1\t1\tpi\n") ==
               [%{name: "pi", active?: true, index: "1", thread_id: nil, opening: nil, activity: nil}]
    end
  end
end
