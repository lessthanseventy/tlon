defmodule Server.StaffingTest do
  # The staffing pass on the server: nothing spawned ahead of need, the cold swept, the orphan
  # sweep, the stale reap and a cut-off turn picked up — driven through the `:tmux_cmd` seam, so no
  # live tmux or harness is ever forked.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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
      "display-message" in args -> {"#{old()}\n", 0}
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
    # borges's mark is older than the warm window but inside the stale-turn clock: mid-turn keeps him
    Application.put_env(:server, :stale_turn_seconds, 3 * 3600)
    on_exit(fn -> Application.delete_env(:server, :stale_turn_seconds) end)
    thread = staffed_thread(ws, "borges")
    session!("hronir", standing.id, 60)
    session!("borges", thread.id, 7_200, true)

    tmux(
      "0\trufus\t\t\t999999991\trufus\t#{old()}\n1\thronir\t\t\t999999992\thronir\t#{old()}\n" <>
        "2\tt#{thread.id}\t#{thread.id}\tdone\t999999993\tborges\t#{old()}\n3\tborges\t\t\t999999994\tborges\t#{fresh()}\n"
    )

    assert :ok = Staffing.pass(ws.id)

    # rufus: no session at all, long past booting — cold
    cold = "#{session}:0"
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^cold]}
    # hronir warm, borges mid-turn on his leaf, borges just booting on the standing thread
    for i <- 1..3, t = "#{session}:#{i}", do: refute_received({:tmux, ["-L", _, "kill-window", "-t", ^t]})
  end

  test "a window kept warm past max_session_hours starts fresh at an idle moment; a busy or young one stays",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")
    four_hours = System.os_time(:second) - 4 * 3600
    # hronir: warm (2 min ago, inside the cache window) but idle, on a 4-hour-old window
    long = session!("hronir", standing.id, 120)
    # borges: mid-turn on an equally old window; rufus: idle but on a young window
    session!("borges", thread.id, 120, true)
    session!("rufus", standing.id, 120)

    tmux(
      "0\thronir\t\t\t999999991\thronir\t#{four_hours}\n" <>
        "1\tt#{thread.id}\t#{thread.id}\tdone\t999999992\tborges\t#{four_hours}\n2\trufus\t\t\t999999993\trufus\t#{old()}\n"
    )

    assert :ok = Staffing.pass(ws.id)

    refreshed = "#{session}:0"
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^refreshed]}
    assert Server.Repo.get!(Server.Session, long.id).ended_at
    for i <- 1..2, t = "#{session}:#{i}", do: refute_received({:tmux, ["-L", _, "kill-window", "-t", ^t]})
  end

  test "a mid-turn mark keeps a cold window only while it is younger than the shared stale-turn setting",
       %{ws: ws, sock: sock, session: session} do
    on_exit(fn -> Application.delete_env(:server, :stale_turn_seconds) end)
    thread = staffed_thread(ws, "borges")
    # marked mid-turn two hours ago, and not warm since
    session!("borges", thread.id, 7_200, true)
    tmux("0\tt#{thread.id}\t#{thread.id}\tdone\t999999991\tborges\t#{old()}\n")
    leaf = "#{session}:0"

    Application.put_env(:server, :stale_turn_seconds, 3 * 3600)
    assert :ok = Staffing.pass(ws.id)
    refute_received {:tmux, ["-L", _, "kill-window", "-t", ^leaf]}

    Application.put_env(:server, :stale_turn_seconds, 600)
    assert :ok = Staffing.pass(ws.id)
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^leaf]}
  end

  test "a mid-turn mark holds off a long window's refresh only while it is younger than the stale-turn setting",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    on_exit(fn -> Application.delete_env(:server, :stale_turn_seconds) end)
    thread = staffed_thread(ws, "borges")
    session!("rufus", standing.id, 120)
    # borges: marked mid-turn 20 minutes ago, on a window older than max_session_hours
    session!("borges", thread.id, 1_200, true)
    four_hours = System.os_time(:second) - 4 * 3600

    tmux(
      "0\trufus\t\t\t999999991\trufus\t#{old()}\n1\tt#{thread.id}\t#{thread.id}\tdone\t999999992\tborges\t#{four_hours}\n"
    )

    leaf = "#{session}:1"

    Application.put_env(:server, :stale_turn_seconds, 3600)
    assert :ok = Staffing.pass(ws.id)
    refute_received {:tmux, ["-L", _, "kill-window", "-t", ^leaf]}

    Application.put_env(:server, :stale_turn_seconds, 600)
    assert :ok = Staffing.pass(ws.id)
    assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", ^leaf]}
  end

  test "an idle session whose window is gone is ended; one whose window still runs stays", %{ws: ws} do
    gone = staffed_thread(ws, "hronir")
    lost = session!("hronir", gone.id, 1_200)
    here = staffed_thread(ws, "borges")
    kept = session!("borges", here.id, 1_200)

    tmux("0\tt#{here.id}\t#{here.id}\tdone\t999999991\tborges\t#{old()}\n")
    assert :ok = Staffing.pass(ws.id)

    assert Server.Repo.get!(Server.Session, lost.id).ended_at
    refute Server.Repo.get!(Server.Session, kept.id).ended_at
  end

  # a switch restaffs thread T from hronir to borges; hronir's session lingers though T's one leaf is borges's
  for {label, agent_col} <- [{"tagged", "borges"}, {"untagged", ""}] do
    test "a #{label} leaf on a restaffed thread keeps the new lead's session and ends the old lead's", %{ws: ws} do
      thread = staffed_thread(ws, "borges")
      old_lead = session!("hronir", thread.id, 1_200)
      new_lead = session!("borges", thread.id, 1_200)

      tmux("0\tt#{thread.id}\t#{thread.id}\tdone\t999999991\t#{unquote(agent_col)}\t#{old()}\n")
      assert :ok = Staffing.pass(ws.id)

      assert Server.Repo.get!(Server.Session, old_lead.id).ended_at
      refute Server.Repo.get!(Server.Session, new_lead.id).ended_at
    end
  end

  test "a mid-turn session from before the tmux server whose window matches is ended, logged, and not told to carry on; one after it stays",
       %{ws: ws} do
    here = staffed_thread(ws, "borges")
    other = staffed_thread(ws, "hronir")
    dead = session!("borges", here.id, 30, true)
    live = session!("hronir", other.id, 30)
    before_tmux = DateTime.utc_now() |> DateTime.add(-7_200) |> DateTime.truncate(:second)
    dead |> Ecto.Changeset.change(pane_ref: "%3", started_at: before_tmux) |> Server.Repo.update!()
    live |> Ecto.Changeset.change(pane_ref: "%4") |> Server.Repo.update!()

    started = System.os_time(:second) - 3_600

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      cond do
        "list-windows" in args ->
          {"0\tt#{here.id}\t#{here.id}\tdone\t999999991\tborges\t#{old()}\n1\tt#{other.id}\t#{other.id}\tdone\t999999992\thronir\t#{old()}\n",
           0}

        "display-message" in args ->
          {"#{started}\n", 0}

        true ->
          {"", 0}
      end
    end)

    log = capture_log(fn -> assert :ok = Staffing.pass(ws.id) end)

    assert Server.Repo.get!(Server.Session, dead.id).ended_at
    refute Server.Repo.get!(Server.Session, live.id).ended_at
    refute Enum.any?(Channel.thread_messages(here), &(&1.body =~ "the machine restarted"))
    assert log =~ "session #{dead.id}" and log =~ "thread #{here.id}" and log =~ "%3"
  end

  test "a mid-turn session from before the tmux server is ended and its coworker still told to carry on", %{ws: ws} do
    thread = staffed_thread(ws, "borges")
    cut = session!("borges", thread.id, 30, true)
    before_tmux = DateTime.utc_now() |> DateTime.add(-7_200) |> DateTime.truncate(:second)
    cut |> Ecto.Changeset.change(pane_ref: "%3", started_at: before_tmux) |> Server.Repo.update!()
    tmux("")

    assert :ok = Staffing.pass(ws.id)

    assert Server.Repo.get!(Server.Session, cut.id).ended_at
    assert Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "@borges the machine restarted"))
  end

  test "a tmux that can't be asked ends nothing: no idle session ended, no cut-off turn announced", %{ws: ws} do
    idle = session!("hronir", staffed_thread(ws, "hronir").id, 1_200)
    thread = staffed_thread(ws, "borges")
    mid = session!("borges", thread.id, 30, true)

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(self(), {:tmux, args})
      if "list-windows" in args, do: {"server exited unexpectedly", 1}, else: {"", 0}
    end)

    assert :ok = Staffing.pass(ws.id)

    refute Server.Repo.get!(Server.Session, idle.id).ended_at
    refute Server.Repo.get!(Server.Session, mid.id).ended_at
    refute Enum.any?(Channel.thread_messages(thread), &(&1.author == "tlon"))
    refute_received {:tmux, ["-L", _, "kill-window" | _]}
  end

  test "a mid-turn mark a day old is a turn a lost connection never ended: its window is swept",
       %{ws: ws, session: session} do
    thread = staffed_thread(ws, "borges")
    session!("borges", thread.id, 86_400, true)

    tmux("0\tt#{thread.id}\t#{thread.id}\tdone\t999999991\tborges\t#{old()}\n")
    assert :ok = Staffing.pass(ws.id)

    stale = "#{session}:0"
    assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^stale]}
  end

  test "a window nobody can be attributed to (a crew role, a hand-made one) is never swept as cold",
       %{ws: ws, session: session} do
    tmux("0\tr12\t\t\t999999991\t\t\n1\tscratch\t\t\t999999992\t\t\n")
    assert :ok = Staffing.pass(ws.id)
    for i <- 0..1, t = "#{session}:#{i}", do: refute_received({:tmux, ["-L", _, "kill-window", "-t", ^t]})
  end

  test "a turn the machine cut off: its session ends and its coworker is told on the thread to carry on",
       %{ws: ws, standing: standing} do
    thread = staffed_thread(ws, "borges")
    cut = session!("borges", thread.id, 30, true)
    alive = session!("hronir", standing.id, 30, true)
    tmux("0\thronir\t\t\t999999991\thronir\t#{fresh()}\n")

    assert :ok = Staffing.pass(ws.id)

    assert Server.Repo.get!(Server.Session, cut.id).ended_at
    assert %{author: "tlon", body: "@borges the machine restarted" <> _} = List.last(Channel.thread_messages(thread))
    # hronir's window is still there: nothing to pick up
    refute Server.Repo.get!(Server.Session, alive.id).ended_at
    refute Enum.any?(Channel.thread_messages(standing), &(&1.author == "tlon"))
  end

  test "a cut turn on a thread that has moved to another lead ends its session and tells nobody",
       %{ws: ws} do
    thread = staffed_thread(ws, "borges")
    cut = session!("borges", thread.id, 30, true)
    {:ok, _} = Channel.assign_lead(thread.id, "hronir")
    tmux("")

    assert :ok = Staffing.pass(ws.id)

    assert Server.Repo.get!(Server.Session, cut.id).ended_at
    refute Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "the machine restarted"))
  end

  test "a cut turn on a leadless thread still tells its agent", %{ws: ws} do
    {:ok, thread} = Channel.open_thread(%{title: "no lead", scope: "machine", workspace_id: ws.id})
    session!("borges", thread.id, 30, true)
    thread |> Ecto.Changeset.change(agent_id: nil) |> Server.Repo.update!()
    tmux("")

    assert :ok = Staffing.pass(ws.id)

    assert Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "@borges the machine restarted"))
  end

  test "clearing a coworker's context ends their sessions and closes their windows, nobody else's",
       %{ws: ws, standing: standing, sock: sock, session: session} do
    thread = staffed_thread(ws, "borges")
    s1 = session!("borges", thread.id, 30)
    s2 = session!("hronir", standing.id, 30)

    tmux(
      "0\thronir\t\t\t999999991\thronir\t#{old()}\n1\tt#{thread.id}\t#{thread.id}\tdone\t999999992\tborges\t#{old()}\n"
    )

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
      "0\trufus\t\t\t999999991\n1\thronir\t\t\t999999992\n2\tborges\t\t\t999999993\n3\tplanner-live\t#{thread.id}\tdone\t999999994\n4\treviewer-stale\t999888\tdone\t999999995\n5\tt777666\t\t\t999999996\n"
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
    tmux("0\tborges\t\t\t999999991\n1\tt#{child.id}\t#{child.id}\t\t999999992\n")

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

  describe "the leaf cap — finish before start, and an idle leaf gives its seat up" do
    setup %{ws: ws} do
      path = Path.join(System.tmp_dir!(), "tlon-cap-#{System.pid()}-#{System.unique_integer([:positive])}.json")
      File.write!(path, ~s({"max_leaves": 1}))
      previous = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, path)

      on_exit(fn ->
        Application.put_env(:server, :operator_config_path, previous)
        File.rm(path)
      end)

      %{ws: ws}
    end

    defp at_stage(thread, stage) do
      thread |> Ecto.Changeset.change(stage: stage) |> Server.Repo.update!()
    end

    defp parked!(thread) do
      :ok = Staffing.note_parked(thread.id)
      thread
    end

    test "a parked review takes the seat of a build leaf whose coworker is idle", %{ws: ws, session: session} do
      build = ws |> staffed_thread("borges") |> at_stage("build")
      session!("borges", build.id, 600)
      ws |> staffed_thread("hronir") |> at_stage("review") |> parked!()

      tmux("0\tt#{build.id}\t#{build.id}\tdone\t999999991\tborges\t#{old()}\n")
      assert :ok = Staffing.pass(ws.id)

      yielded = "#{session}:0"
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^yielded]}
    end

    test "a leaf mid-turn never gives its seat up", %{ws: ws, session: session} do
      build = ws |> staffed_thread("borges") |> at_stage("build")
      session!("borges", build.id, 60, true)
      ws |> staffed_thread("hronir") |> at_stage("review") |> parked!()

      tmux("0\tt#{build.id}\t#{build.id}\tdone\t999999991\tborges\t#{old()}\n")
      assert :ok = Staffing.pass(ws.id)

      busy = "#{session}:0"
      refute_received {:tmux, ["-L", _, "kill-window", "-t", ^busy]}
    end

    test "a parked build never displaces an idle review", %{ws: ws, session: session} do
      review = ws |> staffed_thread("borges") |> at_stage("review")
      session!("borges", review.id, 600)
      ws |> staffed_thread("hronir") |> at_stage("build") |> parked!()

      tmux("0\tt#{review.id}\t#{review.id}\tdone\t999999991\tborges\t#{old()}\n")
      assert :ok = Staffing.pass(ws.id)

      kept = "#{session}:0"
      refute_received {:tmux, ["-L", _, "kill-window", "-t", ^kept]}
    end

    test "the sheriff's beat takes no seat: its idle leaf is never yielded to parked work", %{ws: ws, session: session} do
      beat = staffed_thread(ws, "hronir", "sheriff's beat")
      session!("hronir", beat.id, 600)
      ws |> staffed_thread("borges") |> at_stage("review") |> parked!()

      tmux("0\tt#{beat.id}\t#{beat.id}\tdone\t999999991\thronir\t#{old()}\n")
      assert :ok = Staffing.pass(ws.id)

      duty = "#{session}:0"
      refute_received {:tmux, ["-L", _, "kill-window", "-t", ^duty]}
    end

    test "a free seat goes to the parked thread nearest to shipping", %{ws: ws} do
      review = ws |> staffed_thread("hronir") |> at_stage("review") |> parked!()
      build = ws |> staffed_thread("borges") |> at_stage("build") |> parked!()

      refute Staffing.seat_for?(build, [])
      assert Staffing.seat_for?(review, [])
    end
  end

  describe "hand_off/2 — a running thread goes to another coworker" do
    test "restaffs it, posts the handoff as the operator, and ends the old worker's leaf so the next pass spawns the new one",
         %{ws: ws, sock: sock} do
      thread = staffed_thread(ws, "borges")

      tmux(
        "0\trufus\t\t\t999999991\n1\thronir\t\t\t999999992\n2\tborges\t\t\t999999993\n3\tplanner-task\t#{thread.id}\tdone\t999999994\n"
      )

      assert {:ok, _} = Staffing.hand_off(thread.id, "hronir")

      assert Channel.thread_lead(thread.id) == "hronir"
      assert %{author: "andrew", body: body} = List.last(Channel.thread_messages(thread))
      assert body =~ "@hronir"
      assert_receive {:tmux, ["-L", ^sock, "kill-window", "-t", target]}
      assert target =~ ":3"
    end

    test "an unknown coworker is refused and changes nothing", %{ws: ws} do
      thread = staffed_thread(ws, "borges")
      tmux("0\trufus\t\t\t999999991\n")

      assert {:error, :no_agent} = Staffing.hand_off(thread.id, "nobody")
      assert Channel.thread_lead(thread.id) == "borges"
      refute_received {:tmux, [_, _, "kill-window" | _]}
    end

    test "the manager never leads a workline: handing one to them is refused and changes nothing", %{ws: ws} do
      build = ws |> staffed_thread("borges") |> Ecto.Changeset.change(stage: "build") |> Server.Repo.update!()
      tmux("0\trufus\t\t\t999999991\n")

      assert {:error, :manager_leads_no_workline} = Staffing.hand_off(build.id, "rufus")
      assert Channel.thread_lead(build.id) == "borges"
      assert Channel.thread_messages(build) == []
      refute_received {:tmux, [_, _, "kill-window" | _]}

      plain = staffed_thread(ws, "borges")
      assert {:ok, _} = Staffing.hand_off(plain.id, "rufus")
    end
  end

  test "uqbar's study is a standing duty: its window neither takes a coworker's seat nor waits for one", %{ws: ws} do
    {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
    {:ok, study} = Server.Outside.study(ws.id)
    {:ok, work} = Channel.open_thread(%{title: "plain work", workspace_id: ws.id})

    assert Staffing.duty_thread?(study.id)
    refute Staffing.duty_thread?(work.id)
  end

  test "the Aleph leaves once it has answered: its pane stays until it posts, then retires at idle",
       %{ws: ws, session: session} do
    :ok = Server.Outside.ensure_citizens()
    thread = staffed_thread(ws, "hronir")
    _ = session!("aleph", thread.id, 5)
    tmux("0\taleph\t\t\t999999991\taleph\t#{old()}\n")

    assert :ok = Staffing.pass(ws.id)
    refute_receive {:tmux, ["-L", _, "kill-window" | _]}, 20

    {:ok, _} = Server.Channel.post(%{thread_id: thread.id, author: "aleph", body: "it bends at Workline.advance/2"})
    assert :ok = Staffing.pass(ws.id)
    aleph = "#{session}:0"
    assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^aleph]}

    assert Server.Event
           |> Server.Repo.all()
           |> Enum.any?(&(&1.kind == "pane_retired" and &1.correlation == "pane:aleph"))
  end

  describe "a pane launched with what its profile no longer gives" do
    setup do
      Application.put_env(:server, :retire_stale_launch, true)
      on_exit(fn -> Application.put_env(:server, :retire_stale_launch, false) end)
    end

    defp win(index, name, thread, agent, launch),
      do: "#{index}\t#{name}\t#{thread}\tdone\t99999999#{index}\t#{agent}\t#{old()}\t#{launch}\n"

    test "is retired between turns, one per pass: an idle one now, a mid-turn one once it is idle",
         %{ws: ws, standing: standing, session: session} do
      leaf = staffed_thread(ws, "borges")
      _ = session!("hronir", standing.id, 30)
      busy = session!("borges", leaf.id, 5, true)
      tmux(win(0, "hronir", "", "hronir", "stale") <> win(1, "t#{leaf.id}", leaf.id, "borges", "stale"))

      assert :ok = Staffing.pass(ws.id)
      hronir = "#{session}:0"
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^hronir]}
      refute_receive {:tmux, ["-L", _, "kill-window", "-t", _]}, 20

      assert [%{correlation: "pane:hronir"}] =
               Server.Event |> Server.Repo.all() |> Enum.filter(&(&1.kind == "pane_retired"))

      busy |> Ecto.Changeset.change(thinking_since: nil) |> Server.Repo.update!()
      tmux(win(1, "t#{leaf.id}", leaf.id, "borges", "stale"))
      assert :ok = Staffing.pass(ws.id)
      borges = "#{session}:1"
      assert_receive {:tmux, ["-L", _, "kill-window", "-t", ^borges]}
    end

    test "a pane stamped with what its profile gives now is left alone", %{ws: ws, standing: standing} do
      _ = session!("hronir", standing.id, 30)
      tmux(win(0, "hronir", "", "hronir", Server.Arbiter.Tmux.launch_stamp(ws.id, "hronir")))
      assert Server.Arbiter.Tmux.launch_stamp(ws.id, "hronir") == Server.Arbiter.Tmux.launch_stamp(ws.id, "hronir")

      assert :ok = Staffing.pass(ws.id)
      refute_receive {:tmux, ["-L", _, "kill-window", "-t", _]}, 20
    end

    test "the next session there opens knowing where it left off, and only that one", %{ws: ws} do
      leaf = staffed_thread(ws, "borges")
      {:ok, post} = Server.Channel.post(%{thread_id: leaf.id, author: "borges", body: "plan drafted, committing next"})
      _ = session!("borges", leaf.id, 30)
      tmux(win(1, "t#{leaf.id}", leaf.id, "borges", "stale"))
      assert :ok = Staffing.pass(ws.id)

      note = Staffing.left_off(leaf.id, "borges")
      assert note =~ "Where you left off" and note =~ "its launch changed"
      assert note =~ "##{post.id}" and note =~ "plan drafted, committing next"

      _ = session!("borges", leaf.id, 0)
      assert Staffing.left_off(leaf.id, "borges") == ""
    end
  end

  describe "stale_coworkers/3 — a rename left a process minting under a handle the bench lost" do
    defp tab(name, author),
      do: {%{name: name, index: name, thread_id: nil, opening: nil, pane_pid: 999_999_991}, author}

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

  test "a tmux server that is not up ends no session and posts no restart notice (a restart must not read as every window closed)",
       %{ws: ws} do
    thread = staffed_thread(ws, "borges")
    cut = session!("borges", thread.id, 30, true)
    idle = session!("hronir", thread.id, 30)
    before = length(Channel.thread_messages(thread))

    for out <- [
          "no server running on /tmp/tmux-1000/tlon-workspace-#{ws.id}",
          "error connecting to /tmp/tmux-1000/x (No such file or directory)",
          "can't find session: w#{ws.id}"
        ] do
      Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {out, 1} end)
      assert :ok = Staffing.pass(ws.id)
    end

    refute Server.Repo.get!(Server.Session, cut.id).ended_at
    refute Server.Repo.get!(Server.Session, idle.id).ended_at
    assert length(Channel.thread_messages(thread)) == before
    refute Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "the machine restarted"))
  end

  test "roll_leaf with a tmux that errors logs a warning naming the thread and ends no session", %{ws: ws} do
    thread = staffed_thread(ws, "borges")
    live = session!("borges", thread.id, 30)

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(self(), {:tmux, args})
      if "list-windows" in args, do: {"protocol version mismatch", 1}, else: {"", 0}
    end)

    log = capture_log(fn -> assert :ok = Staffing.roll_leaf(thread) end)

    assert log =~ "thread #{thread.id}" and log =~ "skipped: tmux protocol version mismatch"
    refute Server.Repo.get!(Server.Session, live.id).ended_at
    refute_received {:tmux, ["-L", _, "kill-window" | _]}
  end

  test "with no tmux server up, roll_leaf and clear_context still end the sessions; nothing is logged", %{ws: ws} do
    thread = staffed_thread(ws, "borges")
    live = session!("borges", thread.id, 30)

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      if "list-windows" in args,
        do: {"no server running on /tmp/tmux-1000/tlon-workspace-#{ws.id}", 1},
        else: {"", 0}
    end)

    log =
      capture_log(fn ->
        assert :ok = Staffing.roll_leaf(thread)
        assert :ok = Staffing.clear_context(ws.id, "borges")
      end)

    refute log =~ "skipped"
    assert Server.Repo.get!(Server.Session, live.id).ended_at
  end
end
