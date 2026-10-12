defmodule Server.PauseTest do
  # Pencils down asks the office to stop: nothing new is picked up, and every coworker on a live
  # thread hears to finish its turn and stop. Lights out also stops the verify and landing queues and
  # interrupts every coworker pane. Back to work undoes either. The state lives in the operator's
  # settings file, so a restart keeps it.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Message
  alias Server.Pause

  setup do
    Server.TestDB.clean!()
    path = Path.join(System.tmp_dir!(), "pause-#{System.unique_integer([:positive])}.json")
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

  test "back to work clears the state and tells the lobby; already working, it says nothing", %{lobby: lobby} do
    {:ok, _} = Pause.lights_out()
    assert {:ok, :working} = Pause.back_to_work()
    assert Pause.state() == :working
    assert Enum.any?(bodies(lobby), &(&1 =~ "back to work"))

    before = length(bodies(lobby))
    assert {:ok, :working} = Pause.back_to_work()
    assert length(bodies(lobby)) == before
  end
end
