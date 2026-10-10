defmodule Server.Arbiter.TmuxTest do
  # The server's own terminal backend: spawn a coworker into the workspace's tmux session and
  # wake it by tag, with no UI connected. Two layers — argv assertions through the runner
  # seam, and one REAL tmux run on a throwaway socket (tmux is on every box this runs on).
  use ExUnit.Case, async: false

  alias Server.Arbiter
  alias Server.Channel
  alias Server.Staff
  alias Server.Tmux

  doctest Server.Arbiter.Tmux

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
    handle = %{socket: "tlon-workspace-1", session: "w1", window: "t7"}
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"booting…", 0} end)
    refute Arbiter.Tmux.ready?(handle)
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"❯ \n⏵⏵ auto mode on", 0} end)
    assert Arbiter.Tmux.ready?(handle)
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"tlon: registered — hronir on 7", 0} end)
    assert Arbiter.Tmux.ready?(handle)
  end

  test "spawn: a seat on the bench spawns with its PROFILE's harness — a builder at home is Claude Code, whatever the agent row says; a meta seat too" do
    # the same claude-first default the staffing pass uses; the agent row's `local` engine no longer decides
    # the same claude-first default the staffing pass uses; the agent row's `local` engine no longer decides
    pi_root = Path.join(System.tmp_dir!(), "tlon_arbiter_pi_#{System.pid()}_#{System.unique_integer([:positive])}")
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
        roster: [%{archetype: "builder", name: "hronir"}, %{archetype: "surveyor", name: "tertius"}]
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

    # tertius is never a leaf lead, but a window opened for it still wears its profile, not bare pi
    {:ok, meta} = Channel.open_thread(%{title: "summary", workspace_id: ws.id})
    {:ok, meta} = Staff.assign(meta, Staff.agent_by_name("tertius"))

    meta_exports =
      ~s(export TLON_MCP_URL="http://127.0.0.1:4040/mcp"\nexport TLON_THREAD="#{meta.id}"\nexport TLON_AUTHOR="tertius")

    assert {:ok, _} = Arbiter.Tmux.spawn(meta_exports)
    assert_received {:tmux, ["-L", _, "new-session", "-d", "-s", _, "-n", _, cmd]}
    assert cmd =~ "claude-code/launch.sh"
  end

  test "spawn: an off-shift seat's duty (a nightly schedule, the sheriff's beat) still runs as that seat, not the engine fallback" do
    {:ok, ws} =
      Server.Workspaces.register(%{
        name: "nights",
        type: "code",
        scope: "project",
        repos: [],
        roster: [%{archetype: "builder", name: "hronir"}]
      })

    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "dahlmann", archetype: "builder", crew: "night"})
    {:ok, _} = Server.Shifts.switch(ws.id, "night")
    # hronir is the day crew (the engine on its agent row is `local`); it is night now
    {:ok, thread} = Channel.open_thread(%{title: "nightly gate", workspace_id: ws.id})
    {:ok, thread} = Staff.assign(thread, Staff.agent_by_name("hronir"))

    exports = ~s(export TLON_THREAD="#{thread.id}"\nexport TLON_AUTHOR="hronir")
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"no", 1}, "list-windows" => {"", 1}}))

    assert {:ok, _} = Arbiter.Tmux.spawn(exports)
    assert_received {:tmux, ["-L", _, "new-session", "-d", "-s", _, "-n", _, cmd]}
    assert cmd =~ "claude-code/launch.sh"
    refute cmd =~ "qwen3-coder"
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

  test "spawn: on the standing thread a window per coworker, named for them, tagged with them and its birth — no thread tag",
       %{ws: ws} do
    {:ok, _} = Staff.register_agent(%{name: "hronir", mandate: "m", engine: "pi"})
    {:ok, lobby} = Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
    assert Channel.machine_thread(ws.id).id == lobby.id
    lobby_exports = ~s(export TLON_THREAD="#{lobby.id}"\nexport TLON_AUTHOR="hronir")

    Application.put_env(
      :server,
      :tmux_cmd,
      record(%{"has-session" => {"", 0}, "list-windows" => {"0\ttertius\t\t\t1\ttertius\t1\n", 0}})
    )

    assert {:ok, %{window: "hronir"}} = Arbiter.Tmux.spawn(lobby_exports)
    assert_received {:tmux, ["-L", _, "set-option", "-w", "-t", _, "@funes_agent", "hronir"]}
    assert_received {:tmux, ["-L", _, "set-option", "-w", "-t", _, "@funes_born", born]}
    assert String.to_integer(born) > 0
    refute_received {:tmux, ["-L", _, "set-option", "-w", "-t", _, "@funes_thread", _]}

    # hronir is already up on the lobby: no second window
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"0\thronir\t\t\t1\thronir\t1\n", 0}}))
    assert {:error, :already_running} = Arbiter.Tmux.spawn(lobby_exports)
  end

  test "spawn: a leaf past the cap is refused, and the thread is told once", %{thread: t, exports: exports} do
    leaves = Enum.map_join(1..6, fn i -> "#{i}\tleaf#{i}\t#{900_000 + i}\tdone\t#{i}\tx\t1\n" end)
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"", 0}, "list-windows" => {leaves, 0}}))

    assert {:error, :at_cap} = Arbiter.Tmux.spawn(exports)
    assert {:error, :at_cap} = Arbiter.Tmux.spawn(exports)
    refute_received {:tmux, ["-L", _, "new-window" | _]}
    assert [%{author: "tlon", body: "⏸ parked" <> _}] = Channel.thread_messages(t)
  end

  test "spawn: a parked thread that gets its seat says so, once — a thread never parked says nothing",
       %{thread: t, exports: exports} do
    leaves = Enum.map_join(1..6, fn i -> "#{i}\tleaf#{i}\t#{900_000 + i}\tdone\t#{i}\tx\t1\n" end)
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"", 0}, "list-windows" => {leaves, 0}}))
    assert {:error, :at_cap} = Arbiter.Tmux.spawn(exports)

    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"", 0}, "list-windows" => {"", 1}}))
    assert {:ok, _} = Arbiter.Tmux.spawn(exports)
    assert {:ok, _} = Arbiter.Tmux.spawn(exports)

    assert [_parked, seated] = Channel.thread_messages(t)
    assert seated.kind == "notice" and seated.payload == %{"seated" => "claude-code"}
    assert seated.body == "claude-code sat down on ##{t.id} — spawn me"
    assert [%{id: id}] = Server.Staffing.seated_since(DateTime.add(DateTime.utc_now(), -60))
    assert id == seated.id
    assert [] == Server.Staffing.seated_since(DateTime.add(DateTime.utc_now(), 60))
  end

  test "spawn: a standing duty's leaf takes no seat — at the cap counting it, a work thread still spawns",
       %{ws: ws, exports: exports} do
    {:ok, duty} = Channel.open_thread(%{title: "inbox sweep", scope: "machine", workspace_id: ws.id})

    %{workspace_id: ws.id, kind: "agent", title: "inbox sweep", body: "sweep", cron: "@hourly", standing: true}
    |> Server.Schedule.create_changeset()
    |> Ecto.Changeset.put_change(:thread_id, duty.id)
    |> Server.Repo.insert!()

    work = Enum.map_join(1..5, fn i -> "#{i}\tleaf#{i}\t#{900_000 + i}\tdone\t#{i}\tx\t1\n" end)
    leaves = work <> "6\tt#{duty.id}\t#{duty.id}\tdone\t6\ttertius\t1\n"
    Application.put_env(:server, :tmux_cmd, record(%{"has-session" => {"", 0}, "list-windows" => {leaves, 0}}))

    assert {:ok, _} = Arbiter.Tmux.spawn(exports)
    assert_received {:tmux, ["-L", _, "new-window" | _]}
  end

  test "under systemd, starting a workspace's tmux runs it in a scope of its own — so a restart can't take it; other commands don't",
       %{ws: ws} do
    pid = self()
    Application.put_env(:server, :tmux_scope, true)
    on_exit(fn -> Application.put_env(:server, :tmux_scope, false) end)

    runner = fn cmd, args, _opts ->
      send(pid, {:ran, cmd, args})
      {"", 0}
    end

    Tmux.run(ws.id, ["new-session", "-d", "-s", "w#{ws.id}"], runner: runner)
    assert_received {:ran, "systemd-run", ["--user", "--scope", "--quiet", "--collect", "--slice=tlon.slice", _ | rest]}
    assert ["tmux", "-L", _, "new-session" | _] = rest

    Tmux.run(ws.id, ["list-windows"], runner: runner)
    assert_received {:ran, "tmux", ["-L", _, "list-windows"]}
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

  test "pending?: our text still in the harness's input line — not its echo in the history, not someone else's draft" do
    sent = "New message on thread 1 from andrew: @tertius intake — ticket #13: add first-failure times"

    stuck =
      "● hooks ran\n──────\n❯ New message on thread 1 from andrew: @tertius intake —\n  ticket #13: add first-failure times\n──────\n"

    # a boot that ate the start: what's left is still ours
    eaten = "──────\n❯ ticket #13: add first-failure times\n──────\n"
    taken = "❯ New message on thread 1 from andrew: @tertius intake\n● on it\n──────\n❯ \n──────\n"
    draft = "──────\n❯ andrew typing something else\n──────\n"
    assert Arbiter.Tmux.pending?(stuck, sent) and Arbiter.Tmux.pending?(eaten, sent)
    refute Arbiter.Tmux.pending?(taken, sent)
    refute Arbiter.Tmux.pending?(draft, sent)
  end

  test "pending?: our text on a later line of a draft — a poke typed under an earlier one that never went" do
    first = "New message on thread 145 from tlon: ⧗ approved — in the merge queue: it lands once rebased onto main"
    second = "you have 1 unread message(s) on your threads"

    # hronir's pane: a fresh session's boot ate the first poke's Enters, and the drain's poke landed under it
    both =
      "● agents-md: AGENTS.md loaded\n──────\n❯ #{first}\n  #{second}\n──────\n  ╭─────╮\n  │ ctx 0 │\n  ╰─────╯\n"

    assert Arbiter.Tmux.pending?(both, second)
    assert Arbiter.Tmux.pending?(both, first)
    # the box's border and status lines below the draft are never read as part of it
    refute Arbiter.Tmux.pending?("──────\n❯ \n──────\n  │ #{second} │\n", second)
  end

  test "wake: when the Enter was swallowed — the text still in the input — it presses Enter again", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_confirm_ms, [10])
    on_exit(fn -> Application.delete_env(:server, :tmux_confirm_ms) end)

    Application.put_env(
      :server,
      :tmux_cmd,
      record(%{
        "list-windows" => {"2\tbuilder-spawn-me\t#{t.id}\t9\n", 0},
        "capture-pane" => {"──\n❯ ping from the server\n──\n", 0}
      })
    )

    assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code", pane_ref: nil}, "ping from the server")
    assert_received {:tmux, ["-L", _, "send-keys", "-t", _, "Enter"]}
    assert_receive {:tmux, ["-L", _, "capture-pane" | _]}, 500
    assert_receive {:tmux, ["-L", _, "send-keys", "-t", _, "Enter"]}, 500
  end

  test "wake: a pane that never takes the Enter is pressed at every look, then said so in the log", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_confirm_ms, [5, 5, 5])
    on_exit(fn -> Application.delete_env(:server, :tmux_confirm_ms) end)

    Application.put_env(
      :server,
      :tmux_cmd,
      record(%{
        "list-windows" => {"2\tbuilder-spawn-me\t#{t.id}\t9\n", 0},
        "capture-pane" => {"──\n❯ stuck message\n──\n", 0}
      })
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code", pane_ref: nil}, "stuck message")
        Process.sleep(200)
      end)

    # the first Enter, then one at each of the three looks
    enters = for {:tmux, ["-L", _, "send-keys", "-t", _, "Enter"]} <- collect(), do: :enter
    assert length(enters) == 4
    assert log =~ "still holds its message unsent after every Enter"
  end

  defp collect(acc \\ []) do
    receive do
      m -> collect([m | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "the default looks reach about ten minutes: a slow Claude pane gets its Enter in the end" do
    Application.delete_env(:server, :tmux_confirm_ms)
    assert Enum.sum(Arbiter.Tmux.confirm_delays()) >= 540_000
  end

  test "wake: with no leaf, the lead's own (centre) window by name; none at all is :no_window", %{thread: t} do
    Application.put_env(:server, :tmux_submit_delay_ms, 0)
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"0\tclaude-code\t\t9\n", 0}}))
    assert :ok = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code"}, "hi")
    Application.put_env(:server, :tmux_cmd, record(%{"list-windows" => {"", 0}}))
    assert {:error, :no_window} = Arbiter.Tmux.wake(%{thread_id: t.id, agent: "claude-code"}, "hi")
  end

  test "terminal_target resolves the leaf for a client that wants to attach; nil when nothing runs", %{
    ws: ws,
    thread: t
  } do
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
