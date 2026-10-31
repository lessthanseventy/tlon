defmodule Server.PauseTest do
  # Pencils down asks the office to stop: nothing new is picked up, and every coworker on a live
  # thread hears to finish its turn and stop. Lights out also stops the verify and landing queues and
  # interrupts every coworker pane. Back to work undoes either. The state lives in the operator's
  # settings file, so a restart keeps it.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Pause

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    path = Path.join(System.tmp_dir!(), "pause-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)
    test_pid = self()

    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})
      if "list-windows" in args, do: {"1\tt9\t9\t\t123\temma\t\n2\tlobby\t\t\t124\t\t\n", 0}, else: {"", 0}
    end)

    on_exit(fn ->
      File.rm(path)
      Application.delete_env(:server, :tmux_cmd)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
    {:ok, lobby} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})
    {:ok, busy} = Channel.open_thread(%{title: "the small joys", workspace_id: ws.id})
    {:ok, emma} = Server.Staff.register_agent(%{name: "emma", mandate: "builder", engine: "local"})
    {:ok, _} = Server.Staff.start_session(%{thread_id: busy.id, agent_id: emma.id, pane_ref: "%9"})
    {:ok, quiet} = Channel.open_thread(%{title: "nobody here", workspace_id: ws.id})
    %{ws: ws, lobby: lobby, busy: busy, quiet: quiet}
  end

  defp bodies(thread), do: thread |> Channel.thread_messages() |> Enum.map(& &1.body)

  test "working by default; pencils down tells each live thread once, without waking anyone, and the lobby",
       %{lobby: lobby, busy: busy, quiet: quiet} do
    assert Pause.state() == :working

    assert {:ok, :pencils_down} = Pause.pencils_down()
    assert Pause.state() == :pencils_down

    assert [%Message{kind: "notice", body: body}] =
             busy |> Channel.thread_messages() |> Enum.filter(&(&1.author == "tlon"))

    assert body =~ "pencils down"
    assert body =~ "commit"
    refute Enum.any?(bodies(quiet), &(&1 =~ "pencils down"))
    assert Enum.any?(bodies(lobby), &(&1 =~ "pencils down"))

    assert {:ok, :pencils_down} = Pause.pencils_down()
    assert length(Enum.filter(bodies(busy), &(&1 =~ "pencils down"))) == 1
    refute_received {:tmux, [_, _, "send-keys" | _]}
  end

  test "while paused nothing is picked up: intake routes no ticket and no continuation is posted", %{ws: ws} do
    {:ok, _} = Server.Tickets.file(%{workspace_id: ws.id, title: "a new thing"})
    {:ok, _} = Pause.pencils_down()

    assert :ok = Server.Intake.run(route: fn t -> send(self(), {:routed, t.id}) end)
    refute_received {:routed, _}

    {:ok, wl} = Server.Workline.open(%{title: "owes", slug: "owes", stage: "build", workspace_id: ws.id})
    assert :ok = Server.Workline.Continuation.run(wl.id)
    refute Enum.any?(bodies(wl), &(&1 =~ "↻ continue"))

    {:ok, :working} = Pause.back_to_work()
    assert :ok = Server.Intake.run(route: fn t -> send(self(), {:routed, t.id}) end)
    assert_received {:routed, _}
  end

  test "while paused intake's 30-minute fallback starts nothing; back to work starts it", %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir-i", archetype: "builder"})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "stalled"})
    {:ok, ticket} = Server.Tickets.update(ticket, %{status: "todo"})
    at = DateTime.utc_now() |> DateTime.add(-31 * 60, :second) |> DateTime.truncate(:second)
    Server.Repo.update_all(from(x in Server.Ticket, where: x.id == ^ticket.id), set: [updated_at: at])

    {:ok, _} = Pause.pencils_down()
    assert :ok = Server.Intake.run(route: fn _ -> {:ok, %{}} end)
    assert Server.Tickets.threads_of(ticket.id) == []
    assert %{status: "todo"} = Server.Tickets.get(ticket.id)

    {:ok, :working} = Pause.back_to_work()
    assert :ok = Server.Intake.run(route: fn _ -> {:ok, %{}} end)
    assert [{"promoted", _}] = Server.Tickets.threads_of(ticket.id)
  end

  test "lights out interrupts every coworker pane with Escape, typing nothing", %{ws: ws} do
    assert {:ok, :lights_out} = Pause.lights_out()
    assert Pause.state() == :lights_out

    target = "w#{ws.id}:1"
    assert_received {:tmux, [_, _, "send-keys", "-t", ^target, "Escape"]}
    refute_received {:tmux, [_, _, "send-keys", "-t", _, "Escape"]}
    refute_received {:tmux, [_, _, "send-keys", "-l" | _]}
  end

  test "lights out survives a restart: the boot starts the verify and landing queues paused" do
    oban = [queues: [default: 5, verify: 1, landing: 1], plugins: []]
    assert Server.OperatorConfig.boot_oban(oban)[:queues] == [default: 5, verify: 1, landing: 1]

    {:ok, _} = Pause.lights_out()

    assert Server.OperatorConfig.boot_oban(oban)[:queues] ==
             [default: 5, verify: [limit: 1, paused: true], landing: [limit: 1, paused: true]]
  end

  defp tlon_chats(thread),
    do: thread |> Channel.thread_messages() |> Enum.filter(&(&1.author == "tlon" and &1.kind == "chat"))

  defp live_thread(ws, title, agent, pane) do
    {:ok, thread} = Channel.open_thread(%{title: title, workspace_id: ws.id})
    {:ok, thread} = Server.Staff.assign(thread, agent)
    {:ok, _} = Server.Staff.start_session(%{thread_id: thread.id, agent_id: agent.id, pane_ref: pane})
    thread
  end

  test "back to work wakes each thread pencils down stopped, by its lead as it is now, and skips a closed one",
       %{ws: ws, lobby: lobby, quiet: quiet} do
    emma = Server.Staff.agent_by_name("emma")
    {:ok, daneri} = Server.Staff.register_agent(%{name: "daneri", mandate: "builder", engine: "local"})
    stopped = live_thread(ws, "stopped", emma, "%1")
    done = live_thread(ws, "done since", emma, "%2")
    handed = live_thread(ws, "handed over", emma, "%3")

    {:ok, _} = Pause.pencils_down()
    Server.Repo.update_all(from(t in Server.Thread, where: t.id == ^done.id), set: [state: "closed"])
    {:ok, _} = Server.Staff.assign(handed, daneri)
    {:ok, :working} = Pause.back_to_work()

    assert [%Message{body: "@emma ▶ back to work" <> _}] = tlon_chats(stopped)
    assert [%Message{body: "@daneri ▶ back to work" <> _}] = tlon_chats(handed)
    assert tlon_chats(done) == []
    assert tlon_chats(quiet) == []
    assert Enum.any?(bodies(lobby), &(&1 =~ "▶ back to work: intake"))

    Server.Repo.update_all(from(s in Server.Session, where: s.thread_id == ^stopped.id),
      set: [ended_at: DateTime.utc_now()]
    )

    {:ok, _} = Pause.pencils_down()
    {:ok, :working} = Pause.back_to_work()

    assert length(tlon_chats(stopped)) == 1
    assert length(tlon_chats(handed)) == 2
  end

  test "the back-to-work post wakes the lead: a lead with no session gets a pane spawned", %{ws: ws} do
    Application.put_env(:server, :arbiter, Server.Arbiter.Test)
    Application.put_env(:server, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)

    emma = Server.Staff.agent_by_name("emma")
    {:ok, daneri} = Server.Staff.register_agent(%{name: "daneri", mandate: "builder", engine: "local"})
    handed = live_thread(ws, "handed over", emma, "%3")

    {:ok, _} = Pause.pencils_down()
    {:ok, _} = Server.Staff.assign(handed, daneri)
    {:ok, :working} = Pause.back_to_work()

    [wake] = tlon_chats(handed)
    assert {:pending, _} = Server.Switchboard.deliver(wake)
    assert_received {:spawned, exports}
    assert exports =~ ~s(TLON_AUTHOR="daneri")
    assert exports =~ ~s(TLON_THREAD="#{handed.id}")
    assert_receive {:woke, nil, "New message on thread " <> _}, 1_000
  end

  test "back to work clears the state and tells the lobby; already working, it says nothing", %{lobby: lobby} do
    {:ok, _} = Pause.lights_out()
    assert {:ok, :working} = Pause.back_to_work()
    assert Pause.state() == :working
    assert Enum.any?(bodies(lobby), &(&1 =~ "back to work"))

    before = length(bodies(lobby))
    assert {:ok, :working} = Pause.back_to_work()
    assert length(bodies(lobby)) == before
  end

  describe "auto/1" do
    # compile-time future instants: a past resets_at schedules no resume
    @r5 DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)
    @r5_iso DateTime.to_iso8601(@r5)
    @r5_hm Calendar.strftime(@r5, "%H:%M")
    @r5b DateTime.utc_now() |> DateTime.add(7200) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    @r7 DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    @hot %{five_hour: %{percent: 91, resets_at: @r5_iso}}
    @job %{window: "five_hour", resets_at: @r5_iso}

    test "a window at the threshold while working pauses and says why on the lobby", %{lobby: lobby} do
      assert :ok = Pause.auto(@hot)
      assert Pause.state() == :pencils_down

      assert Enum.any?(
               bodies(lobby),
               &(&1 =~ "5h at 91%" and &1 =~ @r5_hm and &1 =~ "back to work at #{@r5_hm} UTC or when you say")
             )
    end

    test "an auto pause with resets_at enqueues one job at resets_at; performing it resumes and says why", %{
      lobby: lobby
    } do
      Pause.auto(@hot)
      assert_enqueued(worker: Server.Jobs.AutoResume, args: @job, scheduled_at: @r5)
      assert :ok = perform_job(Server.Jobs.AutoResume, @job)
      assert Pause.state() == :working
      assert Enum.any?(bodies(lobby), &(&1 =~ "back to work" and &1 =~ "5h window reset"))
    end

    test "a stale job leaves a later hand pause alone" do
      Pause.auto(@hot)
      {:ok, :working} = Pause.back_to_work()
      {:ok, :pencils_down} = Pause.pencils_down()
      assert :ok = perform_job(Server.Jobs.AutoResume, @job)
      assert Pause.state() == :pencils_down
    end

    test "a stale job from one window leaves another window's auto pause alone" do
      Pause.auto(@hot)
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(%{seven_day: %{percent: 95, resets_at: @r7}})
      assert Pause.state() == :pencils_down
      assert :ok = perform_job(Server.Jobs.AutoResume, @job)
      assert Pause.state() == :pencils_down
    end

    test "a nil resets_at enqueues nothing and the notice says when you say", %{lobby: lobby} do
      Pause.auto(%{seven_day: %{percent: 95, resets_at: nil}})
      refute_enqueued(worker: Server.Jobs.AutoResume)
      assert Enum.any?(bodies(lobby), &(&1 =~ "back to work when you say"))
      refute Enum.any?(bodies(lobby), &(&1 =~ "or when you say"))
    end

    test "a resets_at already past enqueues nothing and the notice says when you say", %{lobby: lobby} do
      Pause.auto(%{five_hour: %{percent: 91, resets_at: "2026-10-27T14:00:00Z"}})
      assert Pause.state() == :pencils_down
      refute_enqueued(worker: Server.Jobs.AutoResume)
      assert Enum.any?(bodies(lobby), &(&1 =~ "back to work when you say"))
      refute Enum.any?(bodies(lobby), &(&1 =~ "or when you say"))
    end

    test "with Oban not running the pause still lands and the notice says when you say", %{lobby: lobby} do
      stop_supervised!(Oban)
      assert :ok = Pause.auto(@hot)
      assert Pause.state() == :pencils_down
      assert Enum.any?(bodies(lobby), &(&1 =~ "back to work when you say"))
    end

    test "lights out after an auto pause is not resumed by the job" do
      Pause.auto(@hot)
      {:ok, :lights_out} = Pause.lights_out()
      assert :ok = perform_job(Server.Jobs.AutoResume, @job)
      assert Pause.state() == :lights_out
    end

    test "below the threshold nothing happens" do
      assert :ok = Pause.auto(%{five_hour: %{percent: 89, resets_at: nil}})
      assert Pause.state() == :working
    end

    test "after back_to_work the same {window, resets_at} does not fire again; a new resets_at does" do
      Pause.auto(@hot)
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(@hot)
      assert Pause.state() == :working
      Pause.auto(%{five_hour: %{percent: 91, resets_at: @r5b}})
      assert Pause.state() == :pencils_down
    end

    test "a manual pause is left as it is, and says nothing", %{lobby: lobby} do
      {:ok, :lights_out} = Pause.lights_out()
      before = bodies(lobby)
      Pause.auto(@hot)
      assert Pause.state() == :lights_out
      assert bodies(lobby) == before
    end

    test "the weekly window counts too", %{lobby: lobby} do
      Pause.auto(%{seven_day: %{percent: 95, resets_at: nil}})
      assert Enum.any?(bodies(lobby), &(&1 =~ "weekly at 95%"))
    end

    test "each window latches on its own: the weekly firing doesn't forget the 5h override" do
      both = %{five_hour: %{percent: 91, resets_at: @r5_iso}, seven_day: %{percent: 92, resets_at: @r7}}

      Pause.auto(both)
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(both)
      assert Pause.state() == :pencils_down
      {:ok, :working} = Pause.back_to_work()
      Pause.auto(both)
      assert Pause.state() == :working
    end
  end
end
