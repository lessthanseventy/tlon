defmodule Server.RolloutTest do
  # After a merge into tlon, what changed says what to roll out: the server, the office TUIs, the
  # desktop shell's bundled room kit.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Rollout

  test "changed paths name the parts they touch" do
    assert Rollout.parts(["server/lib/server/workline.ex", "office/tui/finder.ts", "README.md"]) ==
             MapSet.new([:server, :office_tui])

    assert Rollout.parts(["office/rooms/wide.ts", "office/kit/sim.ts", "adapters/pi/src/mcp.ts"]) ==
             MapSet.new([:office_room, :adapters])

    assert Rollout.parts(["docs/x.md"]) == MapSet.new()
  end

  test "a merge whose range git can't diff says so on the thread instead of raising" do
    {:ok, thread} = Server.Channel.open_thread(%{title: "landed"})

    assert :ok = Rollout.after_merge(%{repo: File.cwd!(), from: "a", to: "b", thread_id: thread.id})

    assert [%{author: "tlon", body: body}] = Server.Channel.thread_messages(thread)
    assert body =~ "rollout unknown"
    assert body =~ "a..b"
  end

  test "a note for the operator is pending until dismissed" do
    GenServer.cast(Rollout, {:note, "pin tlon"})
    assert %{id: id} = Enum.find(Rollout.pending(), &(&1.text == "pin tlon"))
    assert :ok = Rollout.dismiss(id)
    refute Enum.any?(Rollout.pending(), &(&1.id == id))
  end

  test "the office's revision is the tree of office/ on main" do
    assert %{office: sha} = Rollout.revs()
    assert sha == nil or String.length(sha) == 40
  end

  describe "restart/1 — the operator's restart waits for quiet, never refuses" do
    test "busy: scheduled, and it runs (unforced) the moment the last turn ends" do
      me = self()
      run = fn force -> send(me, {:ran, force}) end
      # the test's own busy lines, never Rollout.busy/1: that reads every executing job in the db
      {:ok, mid_turn} = Elixir.Agent.start_link(fn -> ["a coworker is mid-turn on #987655"] end)
      busy = fn -> Elixir.Agent.get(mid_turn, & &1) end
      on_exit(fn -> Rollout.cancel_restart() end)

      assert {:scheduled, lines} = Rollout.restart(run: run, busy: busy, poll_ms: 20)
      assert Enum.any?(lines, &(&1 =~ "#987655"))
      assert Rollout.restart_pending?()
      assert {:scheduled, _} = Rollout.restart(run: run, busy: busy, poll_ms: 20)
      refute_receive {:ran, _}, 60

      Elixir.Agent.update(mid_turn, fn _ -> [] end)
      assert_receive {:ran, false}, 500
      refute_receive {:ran, _}, 100
    end

    test "force: now, whatever is running" do
      me = self()

      Rollout.restart(
        force: true,
        busy: fn -> ["a coworker is mid-turn on #1"] end,
        run: fn force -> send(me, {:ran, force}) end
      )

      assert_received {:ran, true}
    end
  end

  describe "announce_restart/1 — the workers hear a restart" do
    setup do
      Server.TestDB.clean!()
      :ok
    end

    test "every open thread with a live session gets one notice; a thread with none hears nothing" do
      {:ok, agent} = Server.Staff.register_agent(%{name: "ireneo", mandate: "build", engine: "fresh"})
      {:ok, live} = Server.Channel.open_thread(%{title: "live"})
      {:ok, ended} = Server.Channel.open_thread(%{title: "ended"})
      {:ok, _} = Server.Staff.start_session(%{agent_id: agent.id, thread_id: live.id})
      {:ok, s} = Server.Staff.start_session(%{agent_id: agent.id, thread_id: ended.id})
      {:ok, _} = Server.Staff.end_session(s)

      :ok = Rollout.announce_restart("the operator restarted it")

      assert [%{kind: "notice", author: "tlon", body: body}] = Server.Channel.thread_messages(live)
      assert body =~ "the operator restarted it"
      assert Server.Channel.thread_messages(ended) == []
    end
  end

  describe "busy/0 and quiet?/0 — the change window a restart waits for" do
    setup do
      Server.TestDB.clean!()
      :ok
    end

    defp running!(worker, queue, args) do
      {:ok, job} = args |> Oban.Job.new(worker: worker, queue: queue) |> Server.Repo.insert()
      {1, _} = Server.Repo.update_all(where(Oban.Job, id: ^job.id), set: [state: "executing"])
      job
    end

    test "quiet when nobody is mid-turn and no verify or landing runs" do
      assert Rollout.busy(%{}) == []
    end

    test "a running verify or landing is named, and the window is shut" do
      running!("Server.Jobs.Verify", :verify, %{thread_id: 140, slug: "lazy"})
      running!("Server.Jobs.Land", :landing, %{thread_id: 145})
      busy = Rollout.busy(%{})
      assert Enum.any?(busy, &(&1 =~ "verify of #140"))
      assert Enum.any?(busy, &(&1 =~ "landing of #145"))
    end

    test "other queues don't hold the window" do
      running!("Server.Jobs.Drain", :default, %{})
      assert Rollout.busy(%{}) == []
    end

    test "a coworker mid-turn holds it too" do
      assert ["a coworker is mid-turn on #148"] = Rollout.busy(%{148 => ["hronir"]})
    end
  end
end
