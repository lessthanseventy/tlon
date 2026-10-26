defmodule Server.Bench.Contrast do
  @moduledoc """
  The canary A/B a steering change earns on verify: the same role, the same canary tasks, once from
  main's checkout and once from the branch's, and what the contrast was (pass count, tokens, turns).
  Evidence, not a gate: a regression is named for the reviewer (`line/1` ends `REGRESSION`) and never
  turns verify red. Pure rows here; `run/3` shells out to `mix server.bench_roles`.
  """

  alias Server.Workline.Grade

  @max_roles 3
  @timeout_s 900

  @doc """
  The rows for a change touching `paths`; `dirs` = `%{main: root, branch: checkout}`. `[]` when it
  touches no steering. `opts[:exec]` swaps the shell-out (`(dir, args) -> {output, exit}`; the default
  runs `mix` in `<dir>/server` under `timeout #{@timeout_s}`).
  """
  def run(paths, dirs, opts \\ []) do
    exec = opts[:exec] || (&mix/2)
    steering = Grade.steering(paths)
    profiles? = Enum.any?(steering, &match?({:profiles, _}, &1))
    unmeasured = for {:unmeasurable, p} <- steering, do: p
    extra = if unmeasured == [], do: [], else: [unmeasurable(unmeasured)]

    if profiles?, do: bench(dirs, exec) ++ extra, else: extra
  end

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

  defp bench(dirs, exec) do
    with {:ok, main_fp} <- json(exec, dirs.main, ["--fingerprint"]),
         {:ok, branch_fp} <- json(exec, dirs.branch, ["--fingerprint"]) do
      {roles, over} = main_fp |> affected(branch_fp) |> cap()

      rows =
        for role <- roles do
          args = ["--suite", "canary", "--role", role]

          case {json(exec, dirs.main, args), json(exec, dirs.branch, args)} do
            {{:ok, m}, {:ok, b}} -> row(role, m, b)
            {m, b} -> error(String.trim("#{role}: #{why(m)} #{why(b)}"))
          end
        end

      rows ++ if(over == [], do: [], else: [skipped(over)])
    else
      {:error, why} -> [error(why)]
    end
  end

  defp why({:error, w}), do: w
  defp why(_), do: ""

  # one `mix server.bench_roles <args> --out FILE` in `dir`, its JSON read back
  defp json(exec, dir, args) do
    out = Path.join(System.tmp_dir!(), "contrast-#{System.unique_integer([:positive])}.json")

    try do
      case exec.(dir, ["server.bench_roles" | args] ++ ["--out", out]) do
        {_, 0} ->
          {:ok, out |> File.read!() |> JSON.decode!()}

        {text, code} ->
          tail = text |> to_string() |> String.slice(-200, 200)
          {:error, "#{Path.basename(dir)}: bench_roles #{Enum.join(args, " ")} exit #{code}: #{tail}"}
      end
    after
      File.rm(out)
    end
  end

  defp mix(dir, args) do
    System.cmd("timeout", ["#{@timeout_s}", "mise", "exec", "--", "mix" | args],
      cd: Path.join(dir, "server"),
      stderr_to_stdout: true
    )
  end
end
