defmodule Server.Recall.CodeRefsTest do
  use ExUnit.Case, async: true

  alias Server.Recall.CodeRefs

  test "a function ref to a module the project does not own is not a ref" do
    assert CodeRefs.extract("use `Repo.all/1` and `Enum.map/2`") == []
  end

  test "module, path, function and task refs" do
    t = "Server.Maintain.Sweep.run/1 in `server/lib/server/maintain/sweep.ex`; `mise run office:golden`; Server.Fact"

    assert Enum.sort(CodeRefs.extract(t)) ==
             Enum.sort([
               {:module, "Server.Maintain.Sweep"},
               {:function, "run"},
               {:path, "server/lib/server/maintain/sweep.ex"},
               {:task, "office:golden"},
               {:module, "Server.Fact"}
             ])
  end

  test "prose gets no refs", do: assert(CodeRefs.extract("Forgetting is asymmetric in cost.") == [])

  test "an absence claim is skipped",
    do: assert(CodeRefs.extract("Sim.catLetter had no caller in office/sim.ts") == [])
end
