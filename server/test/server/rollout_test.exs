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
