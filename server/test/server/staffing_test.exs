defmodule Server.StaffingTest do
  # The staffing pass on the server: nothing spawned ahead of need, the cold swept, the orphan
  # sweep, the stale reap and a cut-off turn picked up — driven through the `:tmux_cmd` seam, so no
  # live tmux or harness is ever forked.
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
    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)

    %{ws: ws, standing: standing, sock: "tlon-workspace-#{ws.id}", session: "w#{ws.id}"}
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

  # a live session for `agent` on `thread_id`, last active `ago_s` seconds back, mid-turn or not
  defp session!(agent, thread_id, ago_s, thinking? \\ false) do
    a = Server.Staff.agent_by_name(agent)
    {:ok, s} = Server.Staff.start_session(%{agent_id: a.id, thread_id: thread_id})
    at = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -ago_s)
    s |> Ecto.Changeset.change(last_active_at: at, thinking_since: if(thinking?, do: at)) |> Server.Repo.update!()
  end

  defp old, do: System.os_time(:second) - 3_600
  defp fresh, do: System.os_time(:second) - 60

  test "nobody is spawned ahead of need: a pass over an empty workspace opens nothing", %{ws: ws} do
    tmux("")
    assert :ok = Staffing.pass(ws.id)
    refute_received {:tmux, [_, _, "new-session" | _]}
    refute_received {:tmux, [_, _, "new-window" | _]}
  end

  test "a cold coworker's window closes; a warm one, a mid-turn one and one still booting stay",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")
    session!("hronir", standing.id, 60)
    session!("borges", thread.id, 7_200, true)

    tmux(
      "0\trufus\t\t\t1\trufus\t#{old()}\n1\thronir\t\t\t2\thronir\t#{old()}\n" <>
        "2\tt#{thread.id}\t#{thread.id}\tdone\t3\tborges\t#{old()}\n3\tborges\t\t\t4\tborges\t#{fresh()}\n"
    )

    assert :ok = Staffing.pass(ws.id)

    # rufus: no session at all, long past booting — cold
    cold = "#{session}:0"
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^cold]}
    # hronir warm, borges mid-turn on his leaf, borges just booting on the standing thread
    for i <- 1..3, t = "#{session}:#{i}", do: refute_received({:tmux, ["-L", _, "kill-window", "-t", ^t]})
  end

  test "a mid-turn mark a day old is a turn a lost connection never ended: its window is swept",
       %{ws: ws, session: session} do
    thread = staffed_thread(ws, "borges")
    session!("borges", thread.id, 86_400, true)

    tmux("0\tt#{thread.id}\t#{thread.id}\tdone\t1\tborges\t#{old()}\n")
    assert :ok = Staffing.pass(ws.id)

    stale = "#{session}:0"
    assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^stale]}
  end

  test "a window nobody can be attributed to (a crew role, a hand-made one) is never swept as cold",
       %{ws: ws, session: session} do
    tmux("0\tr12\t\t\t1\t\t\n1\tscratch\t\t\t2\t\t\n")
    assert :ok = Staffing.pass(ws.id)
    for i <- 0..1, t = "#{session}:#{i}", do: refute_received({:tmux, ["-L", _, "kill-window", "-t", ^t]})
  end

  test "a turn the machine cut off: its session ends and its coworker is told on the thread to carry on",
       %{ws: ws, standing: standing} do
    thread = staffed_thread(ws, "borges")
    cut = session!("borges", thread.id, 30, true)
    alive = session!("hronir", standing.id, 30, true)
    tmux("0\thronir\t\t\t1\thronir\t#{fresh()}\n")

    assert :ok = Staffing.pass(ws.id)

    assert Server.Repo.get!(Server.Session, cut.id).ended_at
    assert %{author: "tlon", body: "@borges the machine restarted" <> _} = List.last(Channel.thread_messages(thread))
    # hronir's window is still there: nothing to pick up
    refute Server.Repo.get!(Server.Session, alive.id).ended_at
    refute Enum.any?(Channel.thread_messages(standing), &(&1.author == "tlon"))
  end

  test "clearing a coworker's context ends their sessions and closes their windows, nobody else's",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")
    s1 = session!("borges", thread.id, 30)
    s2 = session!("hronir", standing.id, 30)
    tmux("0\thronir\t\t\t1\thronir\t#{old()}\n1\tt#{thread.id}\t#{thread.id}\tdone\t2\tborges\t#{old()}\n")

    assert :ok = Staffing.clear_context(ws.id, "borges")

    assert Server.Repo.get!(Server.Session, s1.id).ended_at
    refute Server.Repo.get!(Server.Session, s2.id).ended_at
    leaf = "#{session}:1"
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^leaf]}
    centre = "#{session}:0"
    refute_received {:tmux, ["-L", _, "kill-window", "-t", ^centre]}
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

  test "a delegated child's leaf (a project-scope thread, as staff_child opens it) is live, not an orphan",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    {:ok, child} = Channel.open_thread(%{title: "finder", workspace_id: ws.id, parent_thread_id: standing.id})
    {:ok, _} = Channel.assign_lead(child.id, "borges")
    tmux("0\tborges\t\t\t1\n1\tt#{child.id}\t#{child.id}\t\t2\n")

    assert :ok = Staffing.pass(ws.id)
    t1 = "#{session}:1"
    refute_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^t1]}, 20
  end

  test "a workspace with no bench is a no-op; pass/0 walks every workspace", %{ws: _ws} do
    {:ok, empty} = Workspaces.register(%{name: "Sylvania", type: "code", scope: "project", repos: [], roster: []})
    tmux("")
    assert :ok = Staffing.pass(empty.id)
    refute_received {:tmux, _}
    assert :ok = Staffing.pass()
    assert_receive {:tmux, ["-L", "tlon-workspace-" <> _ | _]}
  end

  describe "hand_off/2 — a running thread goes to another coworker" do
    test "restaffs it, posts the handoff as the operator, and ends the old worker's leaf so the next pass spawns the new one",
         %{ws: ws, sock: sock} do
      thread = staffed_thread(ws, "borges")
      tmux("0\trufus\t\t\t1\n1\thronir\t\t\t2\n2\tborges\t\t\t3\n3\tplanner-task\t#{thread.id}\tdone\t4\n")

      assert {:ok, _} = Staffing.hand_off(thread.id, "hronir")

      assert Channel.thread_lead(thread.id) == "hronir"
      assert %{author: "andrew", body: body} = List.last(Channel.thread_messages(thread))
      assert body =~ "@hronir"
      assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", target]}
      assert target =~ ":3"
    end

    test "an unknown coworker is refused and changes nothing", %{ws: ws} do
      thread = staffed_thread(ws, "borges")
      tmux("0\trufus\t\t\t1\n")

      assert {:error, :no_agent} = Staffing.hand_off(thread.id, "nobody")
      assert Channel.thread_lead(thread.id) == "borges"
      refute_received {:tmux, [_, _, "kill-window" | _]}
    end
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
