defmodule Server.StaffingTest do
  # The staffing pass on the server (one-brain B/3, lifted from the console's render preamble):
  # the centre, the tail, the leaves under the cap, the orphan sweep and the stale reap — driven
  # through the `:tmux_cmd`/`:staff_join` seams, so no live tmux or harness is ever forked.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Staffing
  alias Server.Workspaces

  @bench [
    %{archetype: "surveyor", name: "rufus"},
    %{archetype: "builder", name: "hronir"},
    %{archetype: "planner", name: "borges"}
  ]

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Freedonia", type: "code", scope: "project", repos: [], roster: @bench})
    # the workspace's standing machine thread — the oldest open one, so it is opened FIRST here
    {:ok, standing} = Channel.open_thread(%{title: "general", scope: "machine", workspace_id: ws.id})

    pi_root = Path.join(System.tmp_dir!(), "tlon_staffing_pi_#{System.unique_integer([:positive])}")
    prior = System.get_env("PI_CODING_AGENT_DIR")
    System.put_env("PI_CODING_AGENT_DIR", Path.join(pi_root, "agent"))
    prior_env = System.get_env("TLON_ENV")
    System.delete_env("TLON_ENV")

    test_pid = self()

    Application.put_env(:server, :staff_join, fn thread_id, agent, opts ->
      send(test_pid, {:join, thread_id, agent, opts})
      {:ok, %{exports: ~s(export TLON_THREAD="#{thread_id}"\nexport TLON_AUTHOR="#{agent}")}}
    end)

    Application.put_env(:server, :staff_poll_ms, 0)
    Application.put_env(:server, :staff_settle_ms, 0)

    on_exit(fn ->
      for k <- [:tmux_cmd, :staff_join, :staff_poll_ms, :staff_settle_ms], do: Application.delete_env(:server, k)
      if prior, do: System.put_env("PI_CODING_AGENT_DIR", prior), else: System.delete_env("PI_CODING_AGENT_DIR")
      if prior_env, do: System.put_env("TLON_ENV", prior_env), else: System.delete_env("TLON_ENV")
      File.rm_rf!(pi_root)
    end)

    %{ws: ws, standing: standing, sock: "console-workspace-#{ws.id}", session: "w#{ws.id}"}
  end

  # A fake tmux: `windows` is what list-windows prints (the centre `rufus` on 0 in most fixtures);
  # everything else succeeds; a capture-pane reports the registered footer (harness ready).
  defp tmux(windows) do
    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      answer(windows, args)
    end)
  end

  defp answer(windows, args) do
    cond do
      "list-windows" in args -> {windows, 0}
      "has-session" in args -> if windows == "", do: {"no", 1}, else: {"", 0}
      "capture-pane" in args -> {"tlon: registered", 0}
      true -> {"", 0}
    end
  end

  defp staffed_thread(ws, handle, title \\ nil) do
    {:ok, thread} = Channel.open_thread(%{title: title || "task for #{handle}", scope: "machine", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(thread.id, handle)
    thread
  end

  test "the centre absent: the bench head's pi opens the session (new-session, the profile's tmux.conf, identity in the env)",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    tmux("")
    assert :ok = Staffing.pass(ws.id)

    assert_receive {:join, tid, "rufus", opts}
    assert tid == standing.id
    assert opts[:mandate] == "machine"
    assert_receive {:tmux, ["-L", ^sock, "-f", conf, "new-session", "-d", "-s", ^session, "-n", "rufus" | rest]}
    assert conf =~ "tmux.conf"
    assert "-e" in rest
    assert Enum.any?(rest, &String.starts_with?(&1, "TLON_AUTHOR=rufus"))
    assert List.last(rest) =~ "PI_CODING_AGENT_DIR"
    assert_receive {:tmux, ["-L", ^sock, "set-option", "-g", "allow-passthrough", "on"]}
  end

  test "a workspace with no machine thread yet: the centre opens one", %{ws: ws} do
    Server.Repo.delete_all(Server.Thread)
    tmux("")
    assert :ok = Staffing.pass(ws.id)
    assert %{scope: "machine", title: "general"} = Channel.machine_thread(ws.id)
  end

  test "the centre up: no new-session; the tail seats get their windows, each by its harness", %{
    ws: ws,
    sock: sock,
    session: session
  } do
    tmux("0\trufus\t\t\t1\n")
    assert :ok = Staffing.pass(ws.id)

    refute_received {:tmux, ["-L", _, "new-session" | _]}
    assert_receive {:tmux, ["-L", ^sock, "new-window", "-d", "-t", ^session, "-n", "hronir", hronir]}
    assert_receive {:tmux, ["-L", ^sock, "new-window", "-d", "-t", ^session, "-n", "borges", borges]}
    # at home the anthropic-model builder and planner ride the official claude launcher
    assert hronir =~ "modules/adapters/claude-code/launch.sh"
    assert borges =~ "modules/adapters/claude-code/launch.sh"
    assert_receive {:join, _tid, "hronir", _}
    assert_receive {:join, _tid, "borges", _}
  end

  test "a staffed worker thread gets a leaf: human name, @funes_thread tag, the operator's message as the opening turn, tagged done",
       %{ws: ws, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "plan the\nrelease"})
    tmux("0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n")

    assert :ok = Staffing.pass(ws.id)

    window = "planner-task-for-borges"
    assert_receive {:join, tid, "borges", opts}
    assert tid == thread.id
    assert opts[:mandate] == "machine"
    assert_receive {:tmux, ["-L", ^sock, "new-window", "-d", "-t", ^session, "-n", ^window, script]}
    assert script =~ "modules/adapters/claude-code/launch.sh"
    tag = "#{thread.id}"
    target = "#{session}:=#{window}"
    assert_receive {:tmux, ["-L", ^sock, "set-option", "-w", "-t", ^target, "@funes_thread", ^tag]}
    assert_receive {:tmux, ["-L", ^sock, "capture-pane", "-p", "-t", ^target]}
    assert_receive {:tmux, ["-L", ^sock, "send-keys", "-l", "-t", ^target, text]}
    assert text == "[server thread ##{thread.id}] andrew: plan the release"
    assert_receive {:tmux, ["-L", ^sock, "send-keys", "-t", ^target, "Enter"]}
    assert_receive {:tmux, ["-L", ^sock, "set-option", "-w", "-t", ^target, "@funes_opening", "done"]}
  end

  test "a live tagged leaf suppresses a respawn; a meta (surveyor) lead never gets one; the standing thread neither",
       %{ws: ws} do
    borges = staffed_thread(ws, "borges")
    _rufus = staffed_thread(ws, "rufus")

    standing =
      Channel.machine_thread(ws.id) ||
        elem(Channel.open_thread(%{title: "general", scope: "machine", workspace_id: ws.id}), 1)

    {:ok, _} = Channel.assign_lead(standing.id, "hronir")
    tmux("0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n3\tplanner-x\t#{borges.id}\tdone\t4\n")

    assert :ok = Staffing.pass(ws.id)

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
  end

  test "a console-era TYPED leaf is submitted and tagged done; a DONE one is left alone", %{
    ws: ws,
    sock: sock,
    session: session
  } do
    thread = staffed_thread(ws, "borges")
    tmux("0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n3\tplanner-x\t#{thread.id}\ttyped\t4\n")

    assert :ok = Staffing.pass(ws.id)

    t3 = "#{session}:3"
    assert_receive {:tmux, ["-L", ^sock, "send-keys", "-t", ^t3, "Enter"]}
    assert_receive {:tmux, ["-L", ^sock, "set-option", "-w", "-t", ^t3, "@funes_opening", "done"]}
    refute_receive {:tmux, ["-L", _, "send-keys", "-l" | _]}, 20
  end

  test "the leaf cap parks a spawn past the budget — no new-window, one durable note", %{ws: ws} do
    cfg = Path.join(System.tmp_dir!(), "tlon_cap_#{System.unique_integer([:positive])}.json")
    File.write!(cfg, ~s({"max_leaves": 1}))
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, cfg)

    on_exit(fn ->
      Application.put_env(:server, :operator_config_path, prior)
      File.rm(cfg)
    end)

    thread = staffed_thread(ws, "borges")
    # one live leaf (of a thread that is still open+staffed) already holds the only seat
    other = staffed_thread(ws, "hronir", "busy")
    tmux("0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n3\tbuilder-busy\t#{other.id}\tdone\t4\n")

    assert :ok = Staffing.pass(ws.id)
    assert :ok = Staffing.pass(ws.id)

    refute_receive {:tmux, ["-L", _, "new-window" | _]}, 50
    assert [%{body: body}] = Channel.thread_messages(Channel.thread(thread.id))
    assert body =~ "parked"
  end

  test "orphan leaves (thread closed while nobody looked) are swept; centre, tail and live leaves are not",
       %{ws: ws, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")

    tmux(
      "0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n3\tplanner-live\t#{thread.id}\tdone\t4\n4\treviewer-stale\t999888\tdone\t5\n5\tt777666\t\t\t6\n"
    )

    assert :ok = Staffing.pass(ws.id)

    [t0, t3, t4, t5] = Enum.map([0, 3, 4, 5], &"#{session}:#{&1}")
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^t4]}
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^t5]}
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", ^t0]}, 20
    refute_receive {:tmux, ["-L", _, "kill-window", "-t", ^t3]}, 20
  end

  test "a workspace with no bench is a no-op; pass/0 walks every workspace", %{ws: _ws} do
    {:ok, empty} = Workspaces.register(%{name: "Sylvania", type: "code", scope: "project", repos: [], roster: []})
    tmux("")
    assert :ok = Staffing.pass(empty.id)
    refute_received {:tmux, _}
    assert :ok = Staffing.pass()
    assert_receive {:tmux, ["-L", "console-workspace-" <> _ | _]}
  end

  describe "stale_coworkers/3 — a rename left a process minting under a handle the bench lost" do
    defp tab(name, author), do: {%{name: name, index: name, thread_id: nil, opening: nil, pane_pid: 1}, author}

    defp check(pairs, bench) do
      tabs = Enum.map(pairs, &elem(&1, 0))
      authors = Map.new(pairs, fn {t, a} -> {t.name, a} end)
      Staffing.stale_coworkers(tabs, bench, fn t -> authors[t.name] end)
    end

    test "a process holding a handle the bench no longer has is stale; one on the bench is not" do
      assert [%{name: "tertius"}] = check([tab("tertius", "tertius-machine")], ["tertius", "hronir"])
      assert check([tab("hronir", "hronir")], ["tertius", "hronir"]) == []
    end

    test "an unreadable process is never stale — we do not kill what we could not identify" do
      assert check([tab("hronir", nil)], ["someone-else"]) == []
    end

    test "the window NAME is not the test — only the identity the process actually holds" do
      assert [%{name: "hronir"}] = check([tab("hronir", "hronir-machine")], ["hronir"])
    end

    test "pane_author is nil for a pid that cannot be read, never a crash" do
      assert Staffing.pane_author(%{pane_pid: 999_999_999}) == nil
      assert Staffing.pane_author(%{pane_pid: nil}) == nil
      assert Staffing.pane_author(%{}) == nil
    end
  end

  test "the pass is on the minute cron" do
    plugins = Application.fetch_env!(:server, Oban)[:plugins]
    {_, cron} = Enum.find(plugins, &match?({Oban.Plugins.Cron, _}, &1))
    assert {"* * * * *", Server.Jobs.Staff} in cron[:crontab]
  end
end
