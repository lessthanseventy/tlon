# Steering evals — CATCH-UP family (worklines slice 0). The dossier/brief is how a fresh or
# rotated agent reconstructs a thread's state (never /resume), so its fidelity IS steering
# config. Runs against the EPHEMERAL eval db `mix funes.eval` provisions — every scenario
# seeds its own thread. Deterministic set gates funes' precommit; the judged scenario needs
# a live judge (`mise run funes:eval`).
alias Server.Channel
alias Server.Dossier
alias Server.Eval.Scenario

brief = fn thread ->
  %Server.Thread{id: thread.id} |> Server.Board.brief() |> Server.MCP.Brief.scope()
end

assert = fn name, run, expect ->
  %Scenario{name: name, family: :catch_up, mode: :assert, run: run, expect: expect}
end

[
  assert.("the brief carries a banked fact", fn ->
    {:ok, thread} = Channel.open_thread(%{title: "eval: banked fact"})
    {:ok, _} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "truecolor needs output mode 5", provenance: "derived"})
    inspect(brief.(thread), limit: :infinity)
  end, &String.contains?(&1, "truecolor needs output mode 5")),
  assert.("the brief carries the open todo", fn ->
    {:ok, thread} = Channel.open_thread(%{title: "eval: open todo"})
    {:ok, _} = Dossier.add_todo(%{thread_id: thread.id, text: "wire the eval scorecard into check"})
    inspect(brief.(thread), limit: :infinity)
  end, &String.contains?(&1, "wire the eval scorecard into check")),
  assert.("a manually forgotten fact leaves the brief", fn ->
    {:ok, thread} = Channel.open_thread(%{title: "eval: forgotten fact"})
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "obsolete eval lore", provenance: "derived"})
    {:ok, _} = Dossier.forget_fact(fact)
    inspect(brief.(thread), limit: :infinity)
  end, &(not String.contains?(&1, "obsolete eval lore"))),
  assert.("a stated constraint pins to the always-loaded set", fn ->
    {:ok, thread} = Channel.open_thread(%{title: "eval: pinned"})
    {:ok, fact} = Dossier.bank_fact(%{thread_id: thread.id, kind: "constraint", text: "never push without the machine gate", provenance: "stated"})
    {fact.id, Enum.map(Dossier.always_loaded_constraints(), & &1.id)}
  end, fn {id, pinned_ids} -> id in pinned_ids end),
  assert.("learnings stay honest about the cut: shown + more = banked", fn ->
    {:ok, thread} = Channel.open_thread(%{title: "eval: honest cut"})

    for n <- 1..8 do
      {:ok, _} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: "learning number #{n}", provenance: "derived"})
    end

    %{shown: shown, more: more} = Server.Recall.thread_learnings(%Server.Thread{id: thread.id})
    {length(shown) + more, 8}
  end, fn {total, banked} -> total == banked end),
  %Scenario{
    name: "a fresh agent can reconstruct state from the brief",
    family: :catch_up,
    mode: :judge,
    run: fn ->
      {:ok, thread} = Channel.open_thread(%{title: "eval: cold-agent catch-up"})
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "andrew", body: "the composer clips long input — fix it"})
      {:ok, _} = Dossier.bank_fact(%{thread_id: thread.id, kind: "decision", text: "reuse Panel.Composer's wrap in machine-chat", provenance: "derived"})
      {:ok, _} = Dossier.add_todo(%{thread_id: thread.id, text: "cap the box at half the body"})
      inspect(brief.(thread), pretty: true, limit: :infinity)
    end,
    judge_prompt: fn rendered ->
      """
      Dimensions: grounding, answerability, actionability.
      The material is a coordination dossier brief for an agent joining a thread cold. The
      thread it summarizes holds EXACTLY three rows: an operator ask about a clipping
      composer, a decision to reuse Panel.Composer's wrap, and a todo to cap the box at half
      the body. Score ONLY whether those three are recoverable from the brief alone —
      grounding: are they present verbatim-or-near; answerability: could the agent state the
      decision; actionability: could it state the next step. A brief surfacing all three is
      a 5 on each. Do NOT penalize terseness or demand content the thread never held.

      #{rendered}
      """
    end
  }
]
