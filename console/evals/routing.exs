# Steering evals — ROUTING family (worklines slice 0). Deterministic: pure functions over the
# staffing pipeline (mention → triage → default), the config that decides who leads a thread.
# Run via `mix aleph.eval`; the deterministic set gates aleph's precommit.
alias Console.MachineChat.Staffing
alias Server.Eval.Scenario

cast = [
  %{"archetype" => "surveyor", "name" => "tertius"},
  %{"archetype" => "builder", "name" => "hronir"},
  %{"archetype" => "reviewer", "name" => "menard"},
  %{"archetype" => "planner", "name" => "celestino"},
  %{"archetype" => "researcher", "name" => "averroes"}
]

default = Staffing.default_coworker(cast)
route = fn text -> Staffing.pick_coworker(text, default, cast) end

assert = fn name, run, expect ->
  %Scenario{name: name, family: :routing, mode: :assert, run: run, expect: expect}
end

[
  assert.("an @-mention wins even when triage keywords disagree", fn ->
    route.("@hronir-machine review this and land it")
  end, &(&1 == "hronir-machine")),
  assert.("an unknown @-handle falls through to triage", fn ->
    route.("@borges-machine review this diff")
  end, &(&1 == "menard-machine")),
  assert.("review intent staffs the reviewer", fn ->
    route.("review the graphics seam PR")
  end, &(&1 == "menard-machine")),
  assert.("plan intent staffs the planner", fn ->
    route.("plan the milestones for worklines")
  end, &(&1 == "celestino-machine")),
  assert.("research intent staffs the researcher", fn ->
    route.("research kitty graphics protocols")
  end, &(&1 == "averroes-machine")),
  assert.("an interrogative opener is research", fn ->
    route.("why does the cache miss on restart?")
  end, &(&1 == "averroes-machine")),
  assert.("'can you fix X?' stays a build ask", fn ->
    route.("can you fix the composer wrap?")
  end, &(&1 == "hronir-machine")),
  assert.("plain build text takes the default builder", fn ->
    route.("wire the OSC 52 yank into leaves")
  end, &(&1 == "hronir-machine")),
  assert.("the surveyor never leads", fn ->
    Staffing.default_coworker([%{"archetype" => "surveyor", "name" => "tertius"}])
  end, &is_nil/1),
  assert.("a builder-less cast falls to its first worker", fn ->
    Staffing.default_coworker([
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "reviewer", "name" => "menard"}
    ])
  end, &(&1 == "menard-machine")),
  assert.("an empty roster resolves nobody", fn ->
    Staffing.pick_coworker("hello there", nil, [])
  end, &is_nil/1),
  assert.("route_reason names why: mention · triage · default", fn ->
    {
      Staffing.route_reason("@hronir-machine go", "hronir-machine", cast),
      Staffing.route_reason("review this diff", "menard-machine", cast),
      Staffing.route_reason("build the thing", "hronir-machine", cast)
    }
  end, &(&1 == {:mention, :triage, :default}))
]
