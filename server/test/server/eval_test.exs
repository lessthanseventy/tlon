defmodule Server.EvalTest do
  # Slice 0 of the worklines design: the steering-config eval harness. The runner is pure —
  # scenarios are data, the judge is a behaviour seam — so the whole scorecard is testable
  # without a model call.
  use ExUnit.Case, async: true

  alias Server.Eval
  alias Server.Eval.Judge.Claude
  alias Server.Eval.Scenario

  defmodule FixedJudge do
    @moduledoc false
    @behaviour Server.Eval.Judge

    @impl true
    def score("good " <> _), do: {:ok, %{scores: %{clarity: 5, grounding: 4}, rationale: "solid"}}
    def score("bad " <> _), do: {:ok, %{scores: %{clarity: 2, grounding: 1}, rationale: "vague"}}
    def score("down " <> _), do: {:error, :judge_unavailable}
  end

  defp assert_scenario(name, value, expect) do
    %Scenario{name: name, family: :routing, mode: :assert, run: fn -> value end, expect: expect}
  end

  defp judge_scenario(name, prompt_prefix) do
    %Scenario{
      name: name,
      family: :catch_up,
      mode: :judge,
      run: fn -> "the brief" end,
      judge_prompt: fn output -> "#{prompt_prefix} #{output}" end
    }
  end

  test "deterministic scenarios pass and fail on their expect" do
    report =
      Eval.run(
        [
          assert_scenario("picks the mention", "hronir-machine", &(&1 == "hronir-machine")),
          assert_scenario("never the surveyor", "tertius-machine", &(&1 != "tertius-machine"))
        ],
        mode: :deterministic
      )

    assert report.passed == 1
    assert report.failed == 1
    assert report.ok? == false
    assert [%{name: "never the surveyor", status: :failed}] = Enum.filter(report.results, &(&1.status == :failed))
  end

  test "a raising scenario is a failure with the error captured, not a crash" do
    report = Eval.run([assert_scenario("boom", :unused, fn _ -> raise "kaput" end)], mode: :deterministic)

    assert report.failed == 1
    assert [%{status: :failed, detail: detail}] = report.results
    assert detail =~ "kaput"
  end

  test "judge mode scores against the threshold: ≥3.5 average passes, below fails" do
    good = Eval.run([judge_scenario("answerable brief", "good")], judge: FixedJudge)
    assert good.judged_avg == 4.5
    assert good.ok?

    bad = Eval.run([judge_scenario("vague brief", "bad")], judge: FixedJudge)
    assert bad.judged_avg == 1.5
    refute bad.ok?
  end

  test "a judge error fails the full run loudly — never a silent skip" do
    report = Eval.run([judge_scenario("judge offline", "down")], judge: FixedJudge)

    assert report.failed == 1
    refute report.ok?
    assert [%{detail: detail}] = report.results
    assert detail =~ "judge_unavailable"
  end

  test "deterministic mode skips judged scenarios and they don't gate the result" do
    report =
      Eval.run(
        [
          assert_scenario("still runs", 1, &(&1 == 1)),
          judge_scenario("needs a model", "good")
        ],
        mode: :deterministic
      )

    assert report.passed == 1
    assert report.skipped == 1
    assert report.ok?
  end

  test "the Claude adapter parses a contract reply, tolerates decoration, refuses garbage" do
    reply = ~s(Sure! {"scores": {"clarity": 4, "grounding": 3}, "rationale": "fine"})
    assert {:ok, %{scores: %{"clarity" => 4, "grounding" => 3}, rationale: "fine"}} = Claude.parse(reply)

    trailing = ~s({"scores": {"clarity": 5}, "rationale": "good"} Note: I used {strict} scoring.)
    assert {:ok, %{scores: %{"clarity" => 5}}} = Claude.parse(trailing)

    assert {:error, {:unparseable_judgement, _}} = Claude.parse("I cannot score this.")
    assert {:error, {:unparseable_judgement, _}} = Claude.parse(~s({"scores": {}, "rationale": "empty"}))
  end

  test "the scorecard renders one line per scenario plus the tally" do
    card =
      [assert_scenario("picks the mention", "x", &(&1 == "x"))]
      |> Eval.run(mode: :deterministic)
      |> Eval.scorecard()

    assert card =~ "picks the mention"
    assert card =~ "1 passed"
  end
end
