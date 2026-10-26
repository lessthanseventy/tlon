defmodule Server.Bench.ContrastTest do
  use ExUnit.Case, async: true

  alias Server.Bench.Contrast

  defp rec(commit, passed, turns) do
    %{
      "commit" => commit,
      "usage" => %{"input" => 100, "output" => 10},
      "tasks" =>
        for i <- 1..2 do
          %{"passed" => i <= passed, "usage" => %{"turns" => turns}}
        end
    }
  end

  test "affected: roles whose prompt hash differs or is new on the branch, sorted" do
    assert Contrast.affected(%{"qa" => "a", "planner" => "b"}, %{"qa" => "a", "planner" => "x", "reviewer" => "y"}) ==
             ["planner", "reviewer"]
  end

  test "cap keeps the first n and names the rest" do
    assert Contrast.cap(~w(a b c d e), 3) == {~w(a b c), ~w(d e)}
  end

  test "summarize sums passes, tokens and turns, and names the commit" do
    assert Contrast.summarize([rec("abc1234", 1, 3)]) ==
             %{passed: 1, total: 2, tokens: 110, turns: 6, commit: "abc1234"}

    assert Contrast.summarize([]) == %{passed: 0, total: 0, tokens: 0, turns: 0, commit: nil}
  end

  test "a branch that passes fewer canaries than main is a regression; equal or better is not" do
    assert %{status: "ok", regression: true} = Contrast.row("qa", [rec("m", 2, 3)], [rec("b", 1, 3)])
    assert %{status: "ok", regression: false} = Contrast.row("qa", [rec("m", 1, 3)], [rec("b", 1, 4)])
    assert %{status: "ok", regression: false} = Contrast.row("qa", [rec("m", 1, 3)], [rec("b", 2, 3)])
  end

  test "a side with no tasks is an error row, never a regression" do
    assert %{status: "error", regression: false} = Contrast.row("qa", [], [rec("b", 2, 3)])
  end

  test "line renders the evidence row, naming a regression" do
    line = Contrast.line(Contrast.row("qa", [rec("m1", 2, 3)], [rec("b1", 1, 4)]))
    assert line == "bench_contrast qa: main 2/2 · branch 1/2 · tokens 110/110 · turns 6/8 · m1..b1 · REGRESSION"
  end

  test "unmeasurable and skipped lines say why nothing was measured" do
    assert Contrast.line(Contrast.unmeasurable(["AGENTS.md"])) ==
             "bench_contrast unmeasurable: AGENTS.md — a seat reads it, the bench never loads it"

    assert Contrast.line(Contrast.skipped(["qa", "reviewer"])) ==
             "bench_contrast skipped: qa, reviewer — over the 3-role cap"
  end
end
