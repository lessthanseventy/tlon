defmodule Server.RolloutTest do
  # After a merge into tlon, what changed says what to roll out: the server, the office TUIs, the
  # desktop shell's bundled room kit.
  use ExUnit.Case, async: false

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
end
