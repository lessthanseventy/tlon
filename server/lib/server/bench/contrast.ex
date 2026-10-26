defmodule Server.Bench.Contrast do
  @moduledoc """
  The canary A/B a steering change earns on verify: the same role, the same canary tasks, once from
  main's checkout and once from the branch's, and what the contrast was (pass count, tokens, turns).
  Evidence, not a gate: a regression is named for the reviewer (`line/1` ends `REGRESSION`) and never
  turns verify red. Pure rows here; `run/3` shells out to `mix server.bench_roles`.
  """

  @max_roles 3

  @doc "Roles whose prompt hash differs between main and the branch (or is new on it), sorted."
  def affected(main_fp, branch_fp) do
    Enum.sort(for({role, h} <- branch_fp, Map.get(main_fp, role) != h, do: role))
  end

  @doc "`{run, skipped}`: the first `n` roles and the rest."
  def cap(roles, n \\ @max_roles), do: Enum.split(roles, n)

  @doc "One side's decoded run records → passes, tokens (in+out), turns, commit."
  def summarize(records) do
    tasks = Enum.flat_map(records, & &1["tasks"])

    %{
      passed: Enum.count(tasks, & &1["passed"]),
      total: length(tasks),
      tokens: records |> Enum.map(&(&1["usage"]["input"] + &1["usage"]["output"])) |> Enum.sum(),
      turns: tasks |> Enum.map(&(&1["usage"]["turns"] || 0)) |> Enum.sum(),
      commit: records |> List.first() |> then(&(&1 && &1["commit"]))
    }
  end

  @doc "The contrast row for `role`: both sides summarized; an empty side is an `error`, never a regression."
  def row(role, main_records, branch_records) do
    {m, b} = {summarize(main_records), summarize(branch_records)}
    ok? = m.total > 0 and b.total > 0

    %{
      kind: :contrast,
      role: role,
      status: if(ok?, do: "ok", else: "error"),
      main: m,
      branch: b,
      regression: ok? and b.passed < m.passed
    }
  end

  def unmeasurable(paths), do: %{kind: :unmeasurable, paths: paths}
  def skipped(roles), do: %{kind: :skipped, roles: roles}
  def error(why), do: %{kind: :error, why: why}

  @doc "The row as the one line recorded as CHECKS evidence and posted to the thread."
  def line(%{kind: :contrast, status: "error", role: r}), do: "bench_contrast #{r}: error — a side ran no tasks"

  def line(%{kind: :contrast, role: r, main: m, branch: b, regression: reg}) do
    "bench_contrast #{r}: main #{m.passed}/#{m.total} · branch #{b.passed}/#{b.total} · " <>
      "tokens #{m.tokens}/#{b.tokens} · turns #{m.turns}/#{b.turns} · #{m.commit}..#{b.commit}" <>
      if(reg, do: " · REGRESSION", else: "")
  end

  def line(%{kind: :unmeasurable, paths: p}),
    do: "bench_contrast unmeasurable: #{Enum.join(p, ", ")} — a seat reads it, the bench never loads it"

  def line(%{kind: :skipped, roles: r}),
    do: "bench_contrast skipped: #{Enum.join(r, ", ")} — over the #{@max_roles}-role cap"

  def line(%{kind: :error, why: w}), do: "bench_contrast error: #{w}"
end
