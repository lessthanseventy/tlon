# #632 plan — canary A/B for steering changes

Spec: `spec.md` (same dir). Run server tests from `server/` with `mise exec -- mix test <file>`; the
gate is `mise run check`. Each task is one commit, test first (red → green). Commit trailer:
`Co-Authored-By: <your model> <noreply@anthropic.com>`.

**Build waits** on `work/verify-s-throwaway-checkout-lives-in-tmp` (edits `scripts/workline-verify.sh`;
gates T7 only) and on the operator's word that `work/t209` (rewrites `roles.ex`, `runner.ex`) is dead
(gates T2–T3). T1, T4, T5, T6 touch neither and may go first.

Shape: one new module `Server.Bench.Contrast` (pure rows + a thin shell-out orchestrator), one new mix
task `server.bench_contrast`, two flags on `server.bench_roles` (`--fingerprint`, `--out`), one
classifier in `Grade`, one block in `workline-verify.sh`, one sentence in the reviewer brief. Evidence
reuses `tlon-cli.sh record-verify` (exit 0, cmd `bench_contrast`) — no new CLI, no new event kind.

---
## T1 — `Grade.steering/1`
Files: `server/lib/server/workline/grade.ex`, `server/test/server/workline/grade_test.exs`.

Test first — append inside `GradeTest` (before final `end`):
```elixir
  describe "steering/1" do
    test "a persona file is canary-able, the law and skills are steering the bench can't load" do
      assert Grade.steering(["server/lib/server/profiles.ex", "server/lib/server/soul.ex"]) ==
               [{:profiles, "server/lib/server/profiles.ex"}, {:profiles, "server/lib/server/soul.ex"}]

      assert Grade.steering(["AGENTS.md", "server/AGENTS.md", "skills/tdd/SKILL.md"]) ==
               [{:unmeasurable, "AGENTS.md"}, {:unmeasurable, "server/AGENTS.md"}, {:unmeasurable, "skills/tdd/SKILL.md"}]
    end

    test "anything else is not steering" do
      assert Grade.steering(["server/lib/server/thread.ex", "office/kit/pets.ts"]) == []
    end
  end
```
Code — in `grade.ex`, after `limits/1`:
```elixir
  @doc """
  The steering a change touches, `[{kind, path}]`: `:profiles` — a file whose edit moves a seat's system
  prompt, which the role bench loads and can A/B — or `:unmeasurable` — a skill or an AGENTS.md/CLAUDE.md,
  which a seat reads but the bench's fixture workdir never loads. Which roles a `:profiles` edit moves is
  `Server.Bench.Contrast`'s question (a prompt fingerprint), not a path's.
  """
  def steering(paths), do: for(p <- paths, kind = steering_kind(p), do: {kind, p})

  defp steering_kind(p) when p in ["server/lib/server/profiles.ex", "server/lib/server/soul.ex"], do: :profiles

  defp steering_kind(p) do
    if Path.basename(p) in ~w(AGENTS.md CLAUDE.md) or p =~ ~r{(^|/)skills/}, do: :unmeasurable
  end
```
Also, **first**, confirm the spec's claim: read `Server.Harness.driver(:claude_code).aside_argv/3`; if it
passes any skill/AGENTS path or setting source that a bench run would load, move that kind to `:profiles`
and say so in the commit. Done: `mix test test/server/workline/grade_test.exs` green.

## T2 — `Roles.fingerprint/1`
Files: `server/lib/server/bench/roles.ex`, `server/test/server/bench/roles_test.exs`.

Test first (new `describe "fingerprint/1"` in `RolesTest`):
```elixir
  describe "fingerprint/1" do
    test "one hash per role over its system prompt; equal prompts equal, an edit differs" do
      same = fn _role -> %{system_prompt: "be terse"} end
      edited = fn role -> %{system_prompt: if(role == "qa", do: "be verbose", else: "be terse")} end

      a = Roles.fingerprint(same)
      assert Map.keys(a) |> Enum.sort() == Roles.roles() |> Map.keys() |> Enum.sort()
      assert Roles.fingerprint(same) == a
      b = Roles.fingerprint(edited)
      assert for({r, h} <- b, h != a[r], do: r) == ["qa"]
    end

    test "a profile with no persona hashes as the empty prompt" do
      assert Roles.fingerprint(fn _ -> %{system_prompt: nil} end) ==
               Roles.fingerprint(fn _ -> %{system_prompt: ""} end)
    end
  end
```
Code (after `roles/0`):
```elixir
  @doc "role => sha256 of the system prompt `profile_fun.(role)` would run it with — what a steering edit moves."
  def fingerprint(profile_fun) do
    Map.new(@roles, fn {role, _} ->
      {role, :crypto.hash(:sha256, profile_fun.(role).system_prompt || "") |> Base.encode16(case: :lower)}
    end)
  end
```
Done: `mix test test/server/bench/roles_test.exs` green.

## T3 — `server.bench_roles --fingerprint` and `--out FILE`
Files: `server/lib/server/bench/roles/runner.ex`, `server/lib/mix/tasks/server.bench_roles.ex`,
`server/test/server/bench/roles_runner_test.exs`.

Test first (in `RunnerTest`):
```elixir
  test "persist/3 writes to --out and leaves the results dir and README alone" do
    dir = Path.join(System.tmp_dir!(), "persist-#{System.unique_integer([:positive])}")
    out = Path.join(dir, "out.json")
    File.mkdir_p!(dir)

    Runner.persist([%{"role" => "qa"}], dir, out)

    assert out |> File.read!() |> JSON.decode!() == [%{"role" => "qa"}]
    refute File.exists?(Path.join(dir, "README.md"))
    refute File.exists?(Path.join(dir, "results"))
    File.rm_rf!(dir)
  end
```
Code — `runner.ex`: replace the two lines at the end of `run/3` (`Roles.append!(…results…)` + `File.write!(…README…)`) with `persist(records, dir, opts[:out])`, keep `records` as the return value, and add:
```elixir
  @doc "Where a run's records go: `out` when given (nothing else touched), else the day's results file and the README."
  def persist(records, dir, nil) do
    Roles.append!(Path.join([dir, "results", "#{Date.utc_today()}.json"]), records)
    File.write!(Path.join(dir, "README.md"), dir |> Path.join("results") |> Roles.history() |> Roles.readme())
  end

  def persist(records, _dir, out), do: Roles.append!(out, records)
```
(`Roles.append!` already `mkdir_p`s and JSON-encodes; atom-keyed records encode to string keys.)

`server.bench_roles.ex`: add `fingerprint: :boolean, out: :string` to the `OptionParser` `strict:`; in `run/1`
add, before the oracle branch:
```elixir
    cond do
      opts[:fingerprint] -> fingerprint!(opts[:out])
      opts[:oracle] -> oracle!(suite, roles)
      true -> run(suite, roles, model, opts[:out])
    end
```
`run/4` passes `out: out` into `Roles.Runner.run(suite, roles, model: model, out: out)`; and
```elixir
  defp fingerprint!(out) do
    Mix.Task.run("app.config")
    fp = Roles.fingerprint(&Roles.Runner.profile(&1, nil))
    if out, do: File.write!(out, JSON.encode!(fp)), else: Mix.shell().info(JSON.encode!(fp))
  end
```
Add both flags to `@moduledoc`. Done: runner test green; by hand
`cd server && mise exec -- mix server.bench_roles --fingerprint --out $TMPDIR/fp.json && jq 'keys' $TMPDIR/fp.json` lists 7 roles.

## T4 — `Server.Bench.Contrast` (pure half)
Files: `server/lib/server/bench/contrast.ex`, `server/test/server/bench/contrast_test.exs`.

Test first:
```elixir
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
```
Code `contrast.ex` (pure half; T5 adds `run/3` below it):
```elixir
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
    for({role, h} <- branch_fp, Map.get(main_fp, role) != h, do: role) |> Enum.sort()
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
    %{kind: :contrast, role: role, status: if(ok?, do: "ok", else: "error"), main: m, branch: b,
      regression: ok? and b.passed < m.passed}
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

  def line(%{kind: :skipped, roles: r}), do: "bench_contrast skipped: #{Enum.join(r, ", ")} — over the #{@max_roles}-role cap"
  def line(%{kind: :error, why: w}), do: "bench_contrast error: #{w}"
end
```
Done: `mix test test/server/bench/contrast_test.exs` green; `mix format --check-formatted`.

## T5 — `Contrast.run/3` (the orchestrator)
Files: same two as T4.

Test first (append):
```elixir
  describe "run/3 with a stubbed executor" do
    # exec.(dir, args) -> {output, exit}; --out FILE is written like the real task writes it
    defp exec(fps, runs) do
      fn dir, args ->
        out = args |> Enum.chunk_every(2, 1, :discard) |> Enum.find_value(fn [k, v] -> k == "--out" && v end)
        side = if dir == "/main/server", do: :main, else: :branch

        body =
          if "--fingerprint" in args, do: fps[side], else: runs[{side, Enum.at(args, Enum.find_index(args, &(&1 == "--role")) + 1)}]

        File.write!(out, JSON.encode!(body))
        {"", 0}
      end
    end

    @fp %{"qa" => "a", "planner" => "a"}

    test "no steering path: nothing runs" do
      assert Contrast.run(["server/lib/server/thread.ex"], %{main: "/main", branch: "/b"}, exec: fn _, _ -> flunk("ran") end) == []
    end

    test "a skill or AGENTS.md alone is one unmeasurable row, nothing runs" do
      assert [%{kind: :unmeasurable, paths: ["AGENTS.md"]}] =
               Contrast.run(["AGENTS.md"], %{main: "/main", branch: "/b"}, exec: fn _, _ -> flunk("ran") end)
    end

    test "a profiles edit benches only the roles whose prompt moved, both sides" do
      ex = exec(%{main: @fp, branch: %{@fp | "qa" => "z"}}, %{{:main, "qa"} => [rec("m", 2, 3)], {:branch, "qa"} => [rec("b", 1, 3)]})
      assert [%{kind: :contrast, role: "qa", regression: true}] =
               Contrast.run(["server/lib/server/profiles.ex"], %{main: "/main", branch: "/b"}, exec: ex)
    end

    test "a main without --fingerprint is an error row, not a crash" do
      ex = fn _, _ -> {"unknown option", 1} end
      assert [%{kind: :error}] = Contrast.run(["server/lib/server/profiles.ex"], %{main: "/main", branch: "/b"}, exec: ex)
    end
  end
```
Code (append to the module):
```elixir
  alias Server.Workline.Grade

  @timeout_s 900

  @doc """
  The rows for a change touching `paths`; `dirs` = `%{main: root, branch: checkout}`. `[]` when it touches no
  steering. `opts[:exec]` swaps the shell-out (`(dir, args) -> {output, exit}`, default: `mix` in `<dir>/server`
  under `timeout #{@timeout_s}`).
  """
  def run(paths, dirs, opts \\ []) do
    exec = opts[:exec] || (&mix/2)
    steering = Grade.steering(paths)
    profiles? = Enum.any?(steering, &match?({:profiles, _}, &1))
    unmeasured = for {:unmeasurable, p} <- steering, do: p
    extra = if unmeasured == [], do: [], else: [unmeasurable(unmeasured)]

    if profiles?, do: bench(dirs, exec) ++ extra, else: extra
  end

  defp bench(dirs, exec) do
    with {:ok, main_fp} <- json(exec, dirs.main, ["--fingerprint"]),
         {:ok, branch_fp} <- json(exec, dirs.branch, ["--fingerprint"]) do
      {roles, over} = main_fp |> affected(branch_fp) |> cap()

      rows =
        for role <- roles do
          args = ["--suite", "canary", "--role", role]

          case {json(exec, dirs.main, args), json(exec, dirs.branch, args)} do
            {{:ok, m}, {:ok, b}} -> row(role, m, b)
            {m, b} -> error("#{role}: #{why(m)} #{why(b)}" |> String.trim())
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
        {_, 0} -> {:ok, out |> File.read!() |> JSON.decode!()}
        {text, code} -> {:error, "#{Path.basename(dir)}: bench_roles #{Enum.join(args, " ")} exit #{code}: #{String.slice(to_string(text), -200, 200)}"}
      end
    after
      File.rm(out)
    end
  end

  defp mix(dir, args) do
    System.cmd("timeout", ["#{@timeout_s}", "mise", "exec", "--", "mix" | args], cd: Path.join(dir, "server"), stderr_to_stdout: true)
  end
```
NB the stub's `exec` receives `dir` = `/main` not `/main/server` — fix the stub to compare `dir == "/main"`
when you write it (the real `mix/2` appends `server`). Done: `mix test test/server/bench/contrast_test.exs` green.

## T6 — the mix task `server.bench_contrast`
Files: `server/lib/mix/tasks/server.bench_contrast.ex`, `server/test/mix/tasks/server_bench_contrast_test.exs` (copy the setup of any existing test in `server/test/mix/tasks/`; if none, test `paths/1` below only).

Code:
```elixir
defmodule Mix.Tasks.Server.BenchContrast do
  @shortdoc "Canary A/B for a branch's steering edits — --branch DIR --main DIR; prints one evidence line per row"
  @moduledoc """
  #{@shortdoc}. What the branch changed against `origin/main` decides (`Server.Workline.Grade.steering/1`);
  a branch that touches no steering prints nothing and runs nothing. Canary tier only, ≤ 3 roles, 15 min a run
  (`Server.Bench.Contrast`). Called by `scripts/workline-verify.sh`, never red: it always exits 0.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Bench.Contrast

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: [branch: :string, main: :string])
    branch = opts[:branch] || Mix.raise("--branch DIR is required")
    main = opts[:main] || Mix.raise("--main DIR is required")

    for row <- Contrast.run(paths(branch), %{main: main, branch: branch}), do: Mix.shell().info(Contrast.line(row))
  end

  @doc false
  def paths(branch) do
    {out, 0} = System.cmd("git", ["-C", branch, "diff", "--name-only", "origin/main", "HEAD"])
    String.split(out, "\n", trim: true)
  end
end
```
Test: `paths/1` on a tmp git repo with an `origin/main` ref (init, commit, `git update-ref refs/remotes/origin/main HEAD`, edit + commit a file) returns exactly the edited file. Done: green.

## T7 — `scripts/workline-verify.sh`: run it, record it, post it
File: `scripts/workline-verify.sh` (this is a gate file: `Grade.limits` makes it wait for the operator — expected).
Test first: `scripts/` has no harness; the proof is T4–T6 plus this negative/positive check by hand, recorded
with `record_check`: in a scratch workline branch, (a) a diff touching only `README.md` →
verify logs no `bench_contrast` line and runs no bench; (b) an edit to a persona string in `profiles.ex` →
a `bench_contrast <role> …` CHECKS row and a thread note appear before `advance`.

Insert after `run_gate "mise run $task" mise run "$task" || fail=1` (and before the `if [ -n "${WORKLINE_GATE:-}" ]` block):
```bash
# A steering edit earns a canary A/B (#632): main's bench against the branch's, as evidence and a note —
# never a red. Only a workline's own verify, only when the gates are green, and only tlon's tree has the task.
if [ "$fail" -eq 0 ] && [ -z "${WORKLINE_GATE:-}" ] && [ "$tid" != - ] && [ -f "$fresh/server/lib/mix/tasks/server.bench_contrast.ex" ]; then
  contrast="$(cd "$fresh/server" && "${clean[@]}" MISE_YES=1 mise exec -- mix server.bench_contrast --branch "$fresh" --main "$root" 2>/dev/null)" || true
  if [ -n "$contrast" ]; then
    while IFS= read -r line; do
      "$cli" record-verify "$tid" "$slug" 0 bench_contrast "$line" || unrecorded=1
    done <<<"$contrast"
    note "$tid" "verify: canary A/B for the steering this branch edits —
$contrast" || true
  fi
fi
```
`timeout 900` per run lives in `Contrast.mix/2`, so the step is bounded by 2 sides × ≤ 3 roles × that, in
practice seconds–minutes per canary. A bench error is an `error` line, never `fail=1`.
Done: both manual checks pass; `mise run check` green.

## T8 — the reviewer sees a regression
Files: `server/lib/server/workline/brief.ex` (the reviewer line, ~l.98), its test (`grep -rn "You are the reviewer, not the builder" server/test` finds it), and the reviewer persona in `server/lib/server/profiles.ex` (`@reviewer_role`).

Test first: assert the reviewer brief contains `bench_contrast` and `REGRESSION`.
Code: append to the reviewer brief sentence: `"If the CHECKS hold a bench_contrast row ending REGRESSION, make it a finding (the branch passes fewer canaries than main; n is small, so say whether it looks like a flake); a green bench_contrast row is not a finding. If a contrast is a real signal either way, propose a habit with propose_habit citing that row."` and the same one-line rule in `@reviewer_role`.
NB T8 edits `profiles.ex` — it is itself steering; the A/B it adds will bench the reviewer on its own landing (good smoke test of the whole chain, expected `error` on the main side until T3 is on main).
Done: brief test green; `mise run check` green.

## Definition of done (the ticket's)
A workline editing a role prompt shows both canary runs on its thread before review (T7b); one that
doesn't runs none (T5 "no steering path", T7a). Record both with `record_check`.
