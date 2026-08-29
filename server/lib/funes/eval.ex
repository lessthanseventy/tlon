defmodule Server.Eval do
  @moduledoc """
  The steering-config eval harness (worklines slice 0): regression coverage for the config
  that steers agents — triage routing, briefs, personas — the way tests cover code.

  Scenarios are data (`Server.Eval.Scenario`), the judge is a behaviour seam, so the runner
  is pure and the whole scorecard is testable without a model call. Two modes:

    * `:all` — deterministic asserts AND judged scenarios (needs a live judge).
    * `:deterministic` — asserts only; judged scenarios are skipped and don't gate. The
      offline mode precommit gates run.

  Pass bar: zero deterministic failures, and (when anything was judged) a judged average
  ≥ #{inspect(3.5)}. A judge error is a FAILURE — the run never silently skips what it
  claimed to judge.
  """

  alias Server.Eval.Scenario

  @threshold 3.5

  @doc "Run scenarios → report `%{results, passed, failed, skipped, judged_avg, ok?}`."
  def run(scenarios, opts \\ []) do
    mode = Keyword.get(opts, :mode, :all)
    judge = Keyword.get(opts, :judge, Server.Eval.Judge.Claude)

    results = Enum.map(scenarios, &result(&1, mode, judge))
    judged_avg = avg(for %{score: score} <- results, score != nil, do: score)
    failed = count(results, :failed)

    %{
      results: results,
      passed: count(results, :passed),
      failed: failed,
      skipped: count(results, :skipped),
      judged_avg: judged_avg,
      ok?: failed == 0 and (judged_avg == nil or judged_avg >= @threshold)
    }
  end

  @doc "Load every `*.exs` scenario file in `dir` — each must evaluate to a scenario list."
  def load(dir) do
    dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn file ->
      {scenarios, _bindings} = Code.eval_file(file)
      scenarios
    end)
  end

  @doc "The human-readable report: one line per scenario, then the tally."
  def scorecard(report) do
    Enum.map_join(report.results, "\n", &line/1) <> "\n" <> tally(report)
  end

  defp result(%Scenario{mode: :assert} = s, _mode, _judge) do
    output = s.run.()
    if s.expect.(output), do: row(s, :passed), else: row(s, :failed, "expect refused #{inspect(output)}")
  rescue
    e -> row(s, :failed, Exception.message(e))
  end

  defp result(%Scenario{mode: :judge} = s, :deterministic, _judge), do: row(s, :skipped)

  defp result(%Scenario{mode: :judge} = s, _mode, judge) do
    output = s.run.()

    case judge.score(s.judge_prompt.(output)) do
      {:ok, %{scores: scores, rationale: rationale}} ->
        s |> row(:scored, rationale) |> Map.put(:score, scores |> Map.values() |> avg())

      {:error, reason} ->
        row(s, :failed, "judge failed: #{inspect(reason)}")
    end
  rescue
    e -> row(s, :failed, Exception.message(e))
  end

  defp row(s, status, detail \\ nil), do: %{name: s.name, family: s.family, status: status, detail: detail, score: nil}

  defp count(results, status), do: Enum.count(results, &(&1.status == status))

  # One rounding rule for both the per-scenario score and the report-level gate average.
  defp avg([]), do: nil
  defp avg(values), do: Float.round(Enum.sum(values) / length(values), 2)

  @doc "The shared CLI contract for the per-module eval mix tasks."
  def mode(argv), do: if("--deterministic" in argv, do: :deterministic, else: :all)

  defp line(%{status: :passed, name: name}), do: "  ✓ #{name}"
  defp line(%{status: :failed, name: name, detail: detail}), do: "  ✗ #{name} — #{detail}"
  defp line(%{status: :skipped, name: name}), do: "  · #{name} (judged — skipped in deterministic mode)"
  defp line(%{status: :scored, name: name, score: score, detail: rationale}), do: "  ★ #{score} #{name} — #{rationale}"

  defp tally(%{judged_avg: nil} = r), do: "#{r.passed} passed · #{r.failed} failed · #{r.skipped} skipped"
  defp tally(r), do: "#{r.passed} passed · #{r.failed} failed · #{r.skipped} skipped · judged avg #{r.judged_avg}/5"
end
