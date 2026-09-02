defmodule Console.CrewTest do
  use ExUnit.Case, async: true

  alias Console.Crew

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  describe "roles/0 and role/1" do
    test "reviewer is a known role with its handle, window prefix, and profile" do
      assert %{handle: "reviewer-machine", window_prefix: "r", profile: "reviewer"} =
               Crew.role("reviewer")
    end

    test "an unknown role is nil" do
      assert Crew.role("nope") == nil
    end

    test "roles/0 lists the MVP crew" do
      assert Crew.roles() |> Map.keys() |> Enum.sort() == ["reviewer"]
    end
  end

  describe "crew_window/2" do
    test "names a per-thread window from role prefix + thread id" do
      assert Crew.crew_window("reviewer", 42) == "r42"
    end

    test "accepts a string thread id" do
      assert Crew.crew_window("reviewer", "42") == "r42"
    end

    test "unknown role raises (a caller must pass a real role)" do
      assert_raise ArgumentError, fn -> Crew.crew_window("planner", 42) end
    end
  end

  describe "handle_role/1 (reverse: a funes handle → its role key)" do
    test "resolves the reviewer handle" do
      assert Crew.handle_role("reviewer-machine") == "reviewer"
    end

    test "a non-crew handle is nil" do
      assert Crew.handle_role("claude-machine") == nil
    end
  end

  describe "spawn_argv/3 and boot_script/2 (pure tmux builders)" do
    test "spawn_argv targets the w<id> session on the console-workspace-<id> socket, window r<id>, detached" do
      argv = Crew.spawn_argv("reviewer", 42, "boot-script-here")

      assert argv == [
               "-L",
               "console-workspace-0",
               "new-window",
               "-d",
               "-t",
               "w0",
               "-n",
               "r42",
               "boot-script-here"
             ]
    end

    test "boot_script sources the funes exports then execs the reviewer profile launcher" do
      script = Crew.boot_script("export TLON_THREAD=\"42\"", "tmux -L aleph-reviewer … 'pi …'")
      assert script =~ "export TERM=xterm-256color"
      assert script =~ "export TLON_THREAD=\"42\""
      assert String.contains?(script, "\nexec tmux -L aleph-reviewer")
    end

    test "kill_argv removes the role's window on the same server" do
      assert Crew.kill_argv("reviewer", 42) ==
               ["-L", "console-workspace-0", "kill-window", "-t", "w0:r42"]
    end
  end

  describe "spawn/3 (IO seam, injected runner)" do
    setup do
      test_pid = self()
      # fake tmux runner: records argv; a capture-pane poll reports the registered footer (pi ready)
      Application.put_env(:console, :crew_cmd, fn
        "tmux", ["-L", _, "capture-pane" | _] = argv, _opts ->
          send(test_pid, {:tmux, argv})
          {"funes: registered — reviewer-machine on 1", 0}

        "tmux", argv, _opts ->
          send(test_pid, {:tmux, argv})
          {"", 0}
      end)

      # fake identity minter: asserts author + thread, returns a canned exports block
      Application.put_env(:console, :crew_join, fn thread_id, author, opts ->
        send(test_pid, {:join, thread_id, author, opts})
        {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}"\nexport TLON_AUTHOR="#{author}")}}
      end)

      # no real poll wait in tests
      Application.put_env(:console, :crew_poll_ms, 0)

      on_exit(fn ->
        Application.delete_env(:console, :crew_cmd)
        Application.delete_env(:console, :crew_join)
        Application.delete_env(:console, :crew_poll_ms)
      end)

      :ok
    end

    test "mints reviewer-machine identity on the thread and spawns the r<id> window" do
      assert {:ok, "r42"} = Crew.spawn("reviewer", 42, "review HEAD~1", inject: false)
      assert_receive {:join, 42, "reviewer-machine", opts}
      assert opts[:mandate] == "machine"
      # the reviewer must NOT hijack the task thread's staffed lead (Staff.assign is single-slot)
      assert opts[:assign] == false
      assert_receive {:tmux, ["-L", _sock, "new-window", "-d", "-t", "w0", "-n", "r42", script]}
      assert script =~ ~s(export TLON_AUTHOR="reviewer-machine")
      assert script =~ "\nexec "
      # a bare harness launch via the profile's driver (Slice D: the anthropic-model reviewer at
      # home rides the official claude launcher), NOT profile_launcher's tmux new-session wrapper —
      # execing new-session here would nest a second tmux server on the shared console-workspace-<id> socket
      assert script =~ "modules/adapters/claude-code/launch.sh"
      refute script =~ "new-session"
    end

    test "an unknown role is an error, no spawn" do
      assert {:error, {:unknown_role, "planner"}} = Crew.spawn("planner", 42, "x")
    end

    test "a nonzero tmux exit is an error, not a crash" do
      test_pid = self()

      Application.put_env(:console, :crew_cmd, fn "tmux", argv, _opts ->
        send(test_pid, {:tmux, argv})
        {"dup window", 1}
      end)

      assert {:error, {:tmux_failed, "dup window"}} = Crew.spawn("reviewer", 42, "x", inject: false)
      assert_receive {:tmux, ["-L", _sock, "new-window" | _]}
    end

    test "injects the opening turn via two-phase send-keys when inject: true (default)" do
      Application.put_env(:console, :crew_settle_ms, 0)
      on_exit(fn -> Application.delete_env(:console, :crew_settle_ms) end)

      assert {:ok, "r42"} = Crew.spawn("reviewer", 42, "review HEAD~1")

      assert_receive {:tmux, ["-L", _sock, "new-window", "-d", "-t", "w0", "-n", "r42", _script]}

      # readiness gate first: the pane is polled before any keystroke, so a booting TUI can't swallow
      # the Enter and strand the turn unsubmitted
      assert_receive {:tmux, ["-L", _sock, "capture-pane", "-p", "-t", "w0:r42"]}

      assert_receive {:tmux, ["-L", sock, "send-keys", "-l", "-t", "w0:r42", text]}
      assert text =~ "thread ##{42}"
      assert text =~ "claude-machine"
      assert text =~ "review HEAD~1"

      assert_receive {:tmux, ["-L", ^sock, "send-keys", "-t", "w0:r42", "Enter"]}
    end

    test "the opening inject waits through a not-yet-ready pane, then submits once registered" do
      Application.put_env(:console, :crew_settle_ms, 0)
      test_pid = self()
      polls = :counters.new(1, [])

      # pane is 'booting' on the first poll, registered on the second — inject must not fire until then
      Application.put_env(:console, :crew_cmd, fn
        "tmux", ["-L", _, "capture-pane" | _] = argv, _opts ->
          send(test_pid, {:tmux, argv})
          :counters.add(polls, 1, 1)
          if :counters.get(polls, 1) >= 2, do: {"funes: registered — reviewer-machine on 1", 0}, else: {"booting…", 0}

        "tmux", argv, _opts ->
          send(test_pid, {:tmux, argv})
          {"", 0}
      end)

      on_exit(fn -> Application.delete_env(:console, :crew_settle_ms) end)

      assert {:ok, "r42"} = Crew.spawn("reviewer", 42, "review HEAD~1")

      assert_receive {:tmux, ["-L", _, "capture-pane", "-p", "-t", "w0:r42"]}
      assert_receive {:tmux, ["-L", _, "capture-pane", "-p", "-t", "w0:r42"]}
      assert_receive {:tmux, ["-L", _, "send-keys", "-l", "-t", "w0:r42", _text]}
      assert_receive {:tmux, ["-L", _, "send-keys", "-t", "w0:r42", "Enter"]}
      assert :counters.get(polls, 1) == 2
    end
  end

  describe "kill/2 (IO seam)" do
    test "kills the role window via the injected runner" do
      test_pid = self()

      Application.put_env(:console, :crew_cmd, fn "tmux", argv, _ ->
        send(test_pid, {:tmux, argv})
        {"", 0}
      end)

      on_exit(fn -> Application.delete_env(:console, :crew_cmd) end)
      assert :ok = Crew.kill("reviewer", 42)
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", "w0:r42"]}
    end
  end

  describe "Server.Crew behaviour (the door funes' spawn_crew/kill_crew tools land in)" do
    setup do
      test_pid = self()

      Application.put_env(:console, :crew_cmd, fn
        "tmux", ["-L", _, "capture-pane" | _] = argv, _opts ->
          send(test_pid, {:tmux, argv})
          {"funes: registered — reviewer-machine on 1", 0}

        "tmux", argv, _opts ->
          send(test_pid, {:tmux, argv})
          {"", 0}
      end)

      Application.put_env(:console, :crew_join, fn thread_id, author, opts ->
        send(test_pid, {:join, thread_id, author, opts})
        {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}")}}
      end)

      Application.put_env(:console, :crew_settle_ms, 0)
      Application.put_env(:console, :crew_poll_ms, 0)

      on_exit(fn ->
        Application.delete_env(:console, :crew_cmd)
        Application.delete_env(:console, :crew_join)
        Application.delete_env(:console, :crew_settle_ms)
        Application.delete_env(:console, :crew_poll_ms)
      end)

      :ok
    end

    test "spawn_role/3 delegates to spawn/4 — mints identity and spawns the window" do
      assert {:ok, "r7"} = Crew.spawn_role("reviewer", 7, "review the diff")
      assert_receive {:join, 7, "reviewer-machine", _opts}
      assert_receive {:tmux, ["-L", _, "new-window", "-d", "-t", "w0", "-n", "r7" | _]}
    end

    test "kill_role/2 delegates to kill/2" do
      assert :ok = Crew.kill_role("reviewer", 7)
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", "w0:r7"]}
    end
  end
end
