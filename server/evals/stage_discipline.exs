# Steering evals — STAGE DISCIPLINE family (worklines slice 2). The stage playbooks are
# advisory governance (skills, not hooks): these gate their load-bearing lines so a
# playbook edit can't silently drop the discipline.
alias Server.Eval.Scenario
alias Server.Thread
alias Server.Workline.Brief

thread = fn stage -> struct!(Thread, %{id: 1, title: "t", slug: "s", stage: stage}) end

assert = fn name, run, expect ->
  %Scenario{name: name, family: :stage_discipline, mode: :assert, run: run, expect: expect}
end

[
  assert.("every working stage's brief names its owed exit artifact and the advance verb", fn ->
    for stage <- ~w(intent spec plan build verify review), do: Brief.stage_message(thread.(stage))
  end, fn briefs ->
    Enum.all?(briefs, &(&1 =~ "advance_stage")) and
      Enum.zip(~w(intent spec plan build verify review), briefs)
      |> Enum.all?(fn
        {"build", b} -> b =~ "work/s"
        {"verify", b} -> b =~ "workline:s:verify"
        {stage, b} -> b =~ "#{stage}.md"
      end)
  end),
  assert.("gated stages tell the worker the exit is the operator's", fn ->
    {Brief.stage_message(thread.("spec")), Brief.stage_message(thread.("plan"))}
  end, fn {spec, plan} ->
    spec =~ "gates on the operator" and not (plan =~ "gates on the operator")
  end),
  assert.("the build playbook carries the failing-test write-fence advisory", fn ->
    Brief.stage_message(thread.("build"))
  end, &(&1 =~ "read-only")),
  assert.("the spec playbook keeps the interview IN the thread", fn ->
    Brief.stage_message(thread.("spec"))
  end, &(&1 =~ "IN THIS THREAD"))
]
