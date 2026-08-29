defmodule Server.Recall.AssembleTest do
  # The working-set assembler's pure core (design:
  # docs/plans/2026-08-19-funes-forgetting-design.md): rank candidates by relevance × strength,
  # keep the pinned constraint floor always, fill a token budget from the top, drop the rest
  # (out of context, not off disk). Pure — no DB.
  use ExUnit.Case, async: true

  alias Server.Recall

  defp cand(id, rel, str, tokens, pinned? \\ false),
    do: %{id: id, relevance: rel, strength: str, tokens: tokens, pinned?: pinned?}

  defp ids(ws), do: Enum.map(ws, & &1.id)

  test "no candidates yields an empty working set" do
    assert Recall.assemble([], budget: 100) == []
  end

  test "pinned constraints are always included, before ranked facts" do
    ws = Recall.assemble([cand(:ranked, 1.0, 5.0, 10), cand(:pin, 0.0, 0.0, 10, true)], budget: 100)
    assert hd(ids(ws)) == :pin
    assert :ranked in ids(ws)
  end

  test "higher relevance × strength ranks first among non-pinned" do
    ws = Recall.assemble([cand(:weak, 0.2, 1.0, 10), cand(:strong, 0.9, 5.0, 10)], budget: 100)
    assert ids(ws) == [:strong, :weak]
  end

  test "the token budget truncates the low-ranked tail" do
    cands = [cand(:a, 1.0, 9.0, 40), cand(:b, 1.0, 5.0, 40), cand(:c, 1.0, 1.0, 40)]
    # budget 100 fits two 40-token facts (80), not three (120)
    assert ids(Recall.assemble(cands, budget: 100)) == [:a, :b]
  end

  test "a dead (non-positive strength) non-pinned fact is dropped" do
    ws = Recall.assemble([cand(:live, 1.0, 2.0, 10), cand(:dead, 1.0, -3.0, 10)], budget: 100)
    assert ids(ws) == [:live]
  end

  test "the pinned floor survives even when it alone exceeds the budget" do
    pinned = [cand(:p1, 0.0, 0.0, 80, true), cand(:p2, 0.0, 0.0, 80, true)]
    ws = Recall.assemble(pinned ++ [cand(:r, 1.0, 9.0, 10)], budget: 100)

    assert :p1 in ids(ws) and :p2 in ids(ws)
    refute :r in ids(ws)
  end
end
