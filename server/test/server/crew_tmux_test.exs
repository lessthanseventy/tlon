defmodule Server.Crew.TmuxTest do
  # The crew backend on the workspace's tmux server (one-brain B/2, lifted from the console): the
  # role's identity is minted on the thread, its profile materialised, its window opened beside the
  # lead, and the opening turn typed only once the pane shows the registered footer.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Crew
  alias Server.Tmux

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "crewed", type: "code", scope: "project", repos: [], roster: []})
    {:ok, thread} = Channel.open_thread(%{title: "review me", workspace_id: ws.id})

    # the profile materialises a config dir — point the pi root at a tmp dir, never the real ~/.pi
    pi_root = Path.join(System.tmp_dir!(), "tlon_crew_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))

    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn
      "tmux", ["-L", _, "capture-pane" | _] = argv, _opts ->
        send(test_pid, {:tmux, argv})
        {"tlon: registered — reviewer on 1", 0}

      "tmux", argv, _opts ->
        send(test_pid, {:tmux, argv})
        {"", 0}
    end)

    Application.put_env(:server, :crew_join, fn thread_id, author, opts ->
      send(test_pid, {:join, thread_id, author, opts})
      {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}"\nexport TLON_AUTHOR="#{author}")}}
    end)

    Application.put_env(:server, :crew_poll_ms, 0)
    Application.put_env(:server, :crew_settle_ms, 0)

    on_exit(fn ->
      for k <- [:tmux_cmd, :crew_join, :crew_poll_ms, :crew_settle_ms], do: Application.delete_env(:server, k)
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      File.rm_rf!(pi_root)
    end)

    %{ws: ws, thread: thread, session: Tmux.session(ws.id)}
  end

  test "the pure role helpers: roles, window names, the reverse lookup" do
    assert %{handle: "reviewer", window_prefix: "r", profile: "reviewer"} = Crew.role("reviewer")
    assert Crew.role("nope") == nil
    assert Map.keys(Crew.roles()) == ["reviewer"]
    assert Crew.crew_window("reviewer", 42) == "r42"
    assert Crew.crew_window("reviewer", "42") == "r42"
    assert_raise ArgumentError, fn -> Crew.crew_window("planner", 42) end
    assert Crew.handle_role("reviewer") == "reviewer"
    assert Crew.handle_role("claude") == nil
  end

  test "spawn mints the reviewer's identity on the thread and opens r<id> in the thread's workspace session",
       %{thread: t, session: session} do
    assert {:ok, "r" <> _} = Crew.Tmux.spawn("reviewer", t.id, "review HEAD~1", inject: false)
    assert_receive {:join, tid, "reviewer", opts}
    assert tid == t.id
    assert opts[:mandate] == "machine"
    # the reviewer must NOT hijack the task thread's staffed lead (Staff.assign is single-slot)
    assert opts[:assign] == false
    window = "r#{t.id}"
    assert_receive {:tmux, ["-L", _, "new-window", "-d", "-t", ^session, "-n", ^window, script]}
    assert script =~ ~s(export TLON_AUTHOR="reviewer")
    assert script =~ "\nexec "
    # the anthropic-model reviewer at home rides the official claude launcher, never a nested tmux
    assert script =~ "modules/adapters/claude-code/launch.sh"
    refute script =~ "new-session"
  end

  test "no session yet → the role opens it (new-session), like the arbiter", %{thread: t, session: session} do
    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn
      "tmux", ["-L", _, "has-session" | _], _opts ->
        {"no", 1}

      "tmux", argv, _opts ->
        send(test_pid, {:tmux, argv})
        {"", 0}
    end)

    assert {:ok, _} = Crew.Tmux.spawn("reviewer", t.id, "x", inject: false)
    assert_receive {:tmux, ["-L", _, "new-session", "-d", "-s", ^session, "-n", _, _]}
  end

  test "typed errors: unknown role, unknown thread, a tmux failure", %{thread: t} do
    assert {:error, {:unknown_role, "planner"}} = Crew.Tmux.spawn("planner", t.id, "x")
    assert {:error, :no_thread} = Crew.Tmux.spawn("reviewer", 999_999, "x")

    Application.put_env(:server, :tmux_cmd, fn "tmux", _argv, _opts -> {"dup window", 1} end)
    assert {:error, {:tmux_failed, "dup window"}} = Crew.Tmux.spawn("reviewer", t.id, "x", inject: false)
  end

  test "the opening turn is polled for readiness, typed, then submitted as its own burst", %{thread: t} do
    test_pid = self()
    polls = :counters.new(1, [])

    Application.put_env(:server, :tmux_cmd, fn
      "tmux", ["-L", _, "capture-pane" | _] = argv, _opts ->
        send(test_pid, {:tmux, argv})
        :counters.add(polls, 1, 1)
        if :counters.get(polls, 1) >= 2, do: {"tlon: registered — reviewer on 1", 0}, else: {"booting…", 0}

      "tmux", argv, _opts ->
        send(test_pid, {:tmux, argv})
        {"", 0}
    end)

    assert {:ok, window} = Crew.Tmux.spawn("reviewer", t.id, "review HEAD~1")
    target = "w#{t.workspace_id}:#{window}"

    assert_receive {:tmux, ["-L", _, "capture-pane", "-p", "-t", ^target]}
    assert_receive {:tmux, ["-L", _, "capture-pane", "-p", "-t", ^target]}
    assert_receive {:tmux, ["-L", _, "send-keys", "-l", "-t", ^target, text]}
    assert text =~ "thread ##{t.id}"
    assert text =~ "claude"
    assert text =~ "review HEAD~1"
    assert_receive {:tmux, ["-L", _, "send-keys", "-t", ^target, "Enter"]}
    assert :counters.get(polls, 1) == 2
  end

  test "kill drops the role's window; a missing thread is a quiet :ok", %{thread: t} do
    assert :ok = Crew.Tmux.kill("reviewer", t.id)
    target = "w#{t.workspace_id}:r#{t.id}"
    assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^target]}
    assert :ok = Crew.Tmux.kill("reviewer", 999_999)
  end

  test "the behaviour doors delegate", %{thread: t} do
    assert {:ok, "r" <> _} = Crew.Tmux.spawn_role("reviewer", t.id, "review the diff")
    assert :ok = Crew.Tmux.kill_role("reviewer", t.id)
  end
end
