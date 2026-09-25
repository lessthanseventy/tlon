defmodule Server.Arbiter.TmuxTest do
  # The server's own terminal backend: spawn a coworker into the workspace's tmux session and
  # wake it by tag, with no cockpit connected. Two layers — argv assertions through the runner
  # seam, and one REAL tmux run on a throwaway socket (tmux is on every box this runs on).
  use ExUnit.Case, async: false

  alias Server.Arbiter
  alias Server.Channel
  alias Server.Staff
  alias Server.Tmux

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "tmuxed", type: "code", scope: "project", repos: [], roster: []})
    {:ok, agent} = Staff.register_agent(%{name: "claude-code", mandate: "m", engine: "claude"})
    {:ok, thread} = Channel.open_thread(%{title: "spawn me", workspace_id: ws.id})
    {:ok, thread} = Staff.assign(thread, agent)

    exports =
      ~s(export TLON_MCP_URL="http://127.0.0.1:4040/mcp"\nexport TLON_THREAD="#{thread.id}"\nexport TLON_AUTHOR="claude-code")

    on_exit(fn ->
      Application.delete_env(:server, :tmux_cmd)
      Application.delete_env(:server, :spawn_launcher_claude)
    end)

    %{ws: ws, thread: thread, exports: exports}
  end

  # A runner that records argv and answers from a script keyed on the tmux subcommand.
  defp record(answers) do
    pid = self()

    fn "tmux", args, _opts ->
      send(pid, {:tmux, args})
      sub = args |> Enum.drop(2) |> List.first()
      Map.get(answers, sub, {"", 0})
    end
  end

  test "ready?: an input line on the pane — pi's registered footer or a harness prompt — else not yet" do
    handle = %{socket: "console-workspace-1", session: "w1", window: "t7"}
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"booting…", 0} end)
    refute Arbiter.Tmux.ready?(handle)
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"❯ \n⏵⏵ auto mode on", 0} end)
    assert Arbiter.Tmux.ready?(handle)
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"tlon: registered — hronir on 7", 0} end)
    assert Arbiter.Tmux.ready?(handle)
  end

  test "spawn: a seat on the bench spawns with its PROFILE's harness — a builder at home is Claude Code, whatever the agent row says" do
    # the same claude-first default the staffing pass uses; the agent row's `local` engine no longer decides
    # the same claude-first default the staffing pass uses; the agent row's `local` engine no longer decides
    pi_root = Path.join(System.tmp_dir!(), "tlon_arbiter_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))

    on_exit(fn ->
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      File.rm_rf!(pi_root)
    end)

    # seating the bench registers the agent row (engine `local`)
    {:ok, ws} =
      Server.Workspaces.register(%{
        name: "benched",
        type: "code",
        scope: "project",
        repos: [],
        roster: [%{archetype: "builder", name: "hronir"}]
      })

    agent = Staff.agent_by_name("hronir")
    {:ok, thread} = Channel.open_thread(%{title: "spawn me", workspace_id: ws.id})
    {:ok, thread} = Staff.assign(thread, agent)

    exports =
      ~s(export TLON_MCP_URL="http://127.0.0.1:4040/mcp"\nexport TLON_THREAD="#{thread.id}"\nexport TLON_AUTHOR="hronir")

    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"no", 1}, "list-windows" => {"", 1}}))

    assert {:ok, _} = Arbiter.Tmux.spawn(exports)
    assert_received {:tmux, ["-L", _, "new-session", "-d", "-s", _, "-n", _, cmd]}
    assert cmd =~ "claude-code/launch.sh"
    refute cmd =~ "exec pi"
  end

  test "spawn: no session yet → new-session -d with the leaf as window 0, tagged; the claude engine gets the claude launcher",
       %{ws: ws, thread: t, exports: exports} do
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"no", 1}, "list-windows" => {"", 1}}))
    Application.put_env(:server, :spawn_launcher_claude, "/opt/claude/launch.sh")
    assert {:ok, %{socket: socket, session: "w" <> _, window: window}} = Arbiter.Tmux.spawn(exports)
    assert socket == Tmux.socket(ws.id)
    assert window == "t#{t.id}"
    assert_received {:tmux, ["-L", _, "list-windows" | _]}
    assert_received {:tmux, ["-L", _, "has-session" | _]}
    assert_received {:tmux, ["-L", _, "new-session", "-d", "-s", _, "-n", ^window, cmd]}
    assert cmd =~ "/bin/sh -c"
    assert cmd =~ "exec /opt/claude/launch.sh"
    assert cmd =~ ~s(TLON_THREAD="#{t.id}")
    assert_received {:tmux, ["-L", _, "set-option", "-w", "-t", _, "@funes_thread", tid]}
    assert tid == Integer.to_string(t.id)
  end

  test "spawn: session up → new-window -d; a thread whose leaf already runs is refused", %{thread: t, exports: exports} do
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"", 0}, "list-windows" => {"", 1}}))
    assert {:ok, _} = Arbiter.Tmux.spawn(exports)
    assert_received {:tmux, ["-L", _, "new-window", "-d", "-t", _, "-n", _, _]}

    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"1\tsomething\t#{t.id}\t123\n", 0}}))
    assert {:error, :already_running} = Arbiter.Tmux.spawn(exports)
  end

  test "spawn: a bad exports block or unknown thread is a typed error", %{} do
    Application.put_env(:server, :tmux_cmd, record(%{}))
    assert {:error, :no_identity_in_exports} = Arbiter.Tmux.spawn("nothing here")
    assert {:error, :no_thread} = Arbiter.Tmux.spawn(~s(export TLON_THREAD="999999"\nexport TLON_AUTHOR="x"))
  end

  test "wake: finds the leaf by @funes_thread tag, types the prompt in one line, then Enter", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"2\tbuilder-spawn-me\t#{t.id}\t9\n", 0}}))
    assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code", pane_ref: nil}, "hello\nthere   friend")
    assert_received {:tmux, ["-L", _, "send-keys", "-l", "-t", target, "hello there friend"]}
    assert target =~ ":2"
    assert_received {:tmux, ["-L", _, "send-keys", "-t", _, "Enter"]}
  end

  test "wake: with no leaf, the lead's own (centre) window by name; none at all is :no_window", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"0\tclaude-code\t\t9\n", 0}}))
    assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code"}, "hi")
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"", 0}}))
    assert {:error, :no_window} = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code"}, "hi")
  end

  test "terminal_target resolves the leaf for a client that wants to attach; nil when nothing runs", %{ws: ws, thread: t} do
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"3\tt#{t.id}\t\t9\n", 0}}))
    assert %{socket: s, session: "w" <> _, window: w} = Arbiter.Tmux.terminal_target(t)
    assert s == Tmux.socket(ws.id) and w == "t#{t.id}"
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"", 1}}))
    assert Arbiter.Tmux.terminal_target(t) == nil
  end

  @tag :tmux
  test "REAL tmux: spawn onto a throwaway socket, the window carries the tag, a wake reaches its input", %{
    ws: ws,
    thread: t,
    exports: exports
  } do
    # the socket is the workspace's, so the test workspace id must be one no live workspace uses;
    # a fresh test DB numbers from 1 — guard the operator's real server by renaming the socket
    sock = "tlon-test-#{System.unique_integer([:positive])}"
    runner = fn "tmux", ["-L", _ | rest], opts -> System.cmd("tmux", ["-L", sock | rest], opts) end
    Application.put_env(:server, :tmux_cmd, runner)
    Application.put_env(:server, :tmux_submit_delay_ms, 100)
    # `cat` echoes what it is sent — the cheapest thing that shows a wake arrived
    Application.put_env(:server, :spawn_launcher_claude, "cat")
    on_exit(fn -> System.cmd("tmux", ["-L", sock, "kill-server"], stderr_to_stdout: true) end)

    assert {:ok, %{window: window}} = Arbiter.Tmux.spawn(exports)
    Process.sleep(300)
    tabs = Tmux.list_windows(ws.id)
    assert %{thread_id: tid} = Tmux.leaf_tab(tabs, t.id)
    assert tid == t.id and window == "t#{t.id}"

    assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code"}, "ping from the server")
    Process.sleep(300)

    {pane, 0} =
      System.cmd("tmux", ["-L", sock, "capture-pane", "-p", "-t", Tmux.target(ws.id, window)], stderr_to_stdout: true)

    assert pane =~ "ping from the server"
  end

  test "wake: a %Server.Session{} row (the drain's shape) resolves its agent by id", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"0\tclaude-code\t\t\t9\n", 0}}))
    agent = Staff.agent_by_name("claude-code")
    {:ok, session} = Staff.start_session(%{thread_id: t.id, agent_id: agent.id, pane_ref: "%0"})
    assert :ok = Arbiter.Tmux.wake(session, "hi")
    assert_received {:tmux, ["-L", _, "send-keys", "-l", "-t", target, "hi"]}
    assert target =~ ":0"
  end
end
