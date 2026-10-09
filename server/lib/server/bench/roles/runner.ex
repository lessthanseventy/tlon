defmodule Server.Bench.Roles.Runner do
  @moduledoc """
  Runs the role bench (`Server.Bench.Roles` holds the format and the pure parts): for each role,
  the profile a coworker of it would get (`Server.Profiles.instantiate/2`, workspace-less, the
  model routed by its grade or `--model`), each of the suite's tasks in a throwaway workdir under
  the system tmp dir — a builder's fixture repo copied in and committed — through that harness
  headless, graded, and the run appended to `bench/roles/results/<date>.json` with the README
  regenerated. It reads no database and writes nothing outside the workdirs and `bench/roles/`.
  """

  alias Server.Bench.Roles
  alias Server.OperatorConfig
  alias Server.Profile
  alias Server.Profiles

  @timeout_s %{"builder" => 900, "senior" => 1800}
  @default_timeout_s 300
  @check_timeout_s 300

  @doc """
  Run `suite` for `roles` (role names), each on its routed model or `opts[:model]` (a model map).
  Returns the records written. `opts[:judge]` swaps the judge, `opts[:dir]` the bench dir.
  """
  def run(suite, roles, opts \\ []) do
    dir = opts[:dir] || Path.join(Profiles.tlon_root(), "bench/roles")
    judge = opts[:judge] || Server.Eval.Judge.Claude
    commit = commit()

    records =
      for role <- roles do
        p = profile(role, opts[:model])
        tasks = Roles.load(Path.join(dir, "tasks"), Roles.roles()[role].set, suite)

        info(
          "#{role} on #{p.model.provider}/#{p.model.model} (#{p.model.thinking}, #{p.harness}): #{length(tasks)} tasks"
        )

        started = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        results = Enum.map(tasks, &run_task(p, &1, judge))

        Roles.record(
          %{
            role: role,
            archetype: p.archetype,
            grade: Roles.roles()[role].grade,
            model: "#{p.model.provider}/#{p.model.model}",
            effort: p.model.thinking,
            harness: p.harness,
            commit: commit,
            suite: suite,
            started_at: started
          },
          results
        )
      end

    Roles.append!(Path.join([dir, "results", "#{Date.utc_today()}.json"]), records)
    File.write!(Path.join(dir, "README.md"), dir |> Path.join("results") |> Roles.history() |> Roles.readme())
    records
  end

  @doc "The profile a coworker of `role` would run as, on `override` when given."
  def profile(role, override) do
    r = Map.fetch!(Roles.roles(), role)
    archetypes = Profiles.archetypes()
    model = Roles.model(r, override, archetypes, &OperatorConfig.grade_model/1)

    if Map.has_key?(archetypes, r.archetype) do
      Profiles.instantiate(%{archetype: r.archetype, name: "bench-#{role}", model: model})
    else
      # an archetype this commit doesn't have yet: its model, no persona
      %Profile{
        name: "bench-#{role}",
        archetype: r.archetype,
        model: model,
        harness: Server.Harness.resolve(model, OperatorConfig.environment())
      }
    end
  end

  defp run_task(profile, task, judge) do
    work = Path.join(System.tmp_dir!(), "tlon-bench-#{task.set}-#{task.id}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)
    if task.repo, do: seed(task.repo, work)
    if task.snapshot, do: seed_snapshot(task.snapshot["parent"], work)
    env = task_env(task)

    t0 = System.monotonic_time(:millisecond)
    timeout = Map.get(@timeout_s, task.set, @default_timeout_s)
    {out, code} = sh(Roles.argv(profile, task.prompt, task.set in ["builder", "senior"]), work, timeout, false, env)
    wall = (System.monotonic_time(:millisecond) - t0) / 1000
    {reply, usage} = Roles.parse_output(profile.harness, out)

    grade = grade(task, reply, work, judge, env)
    File.rm_rf!(work)
    drop_database(env)

    detail = if code == 0, do: grade.detail, else: "harness exit #{code}; #{grade.detail}"
    info("  #{if grade.passed, do: "✓", else: "✗"} #{task.tier}/#{task.id} #{Float.round(wall, 1)}s — #{detail}")

    %{
      id: task.id,
      tier: task.tier,
      passed: grade.passed,
      score: grade.score,
      detail: detail,
      wall_s: wall,
      usage: usage
    }
  end

  defp grade(%{grader: %{"kind" => "json"} = g}, reply, _work, _judge, _env), do: Roles.grade_json(g, reply)

  defp grade(%{grader: %{"kind" => "judge"} = g} = task, reply, _work, judge, _env),
    do: Roles.grade_judged(g, judge.score(Roles.judge_prompt(g, task.prompt, reply)))

  defp grade(%{grader: %{"kind" => "check"}} = task, _reply, work, _judge, env), do: check(task, work, env)

  @doc """
  Run a `check` task's acceptance command in `work` (its `check/` files copied over first) with
  `env`: `%{passed, score: nil, detail}`.
  """
  def check(%{grader: %{"cmd" => cmd}} = task, work, env) do
    hidden = Path.join(task.dir, "check")
    if File.dir?(hidden), do: File.cp_r!(hidden, work)
    {out, code} = sh(["sh", "-c", cmd], work, @check_timeout_s, true, env)
    detail = if code == 0, do: "ok", else: "check exit #{code}: " <> (out |> String.trim() |> String.slice(-300, 300))
    %{passed: code == 0, score: nil, detail: detail}
  end

  @doc """
  The env a task's shell commands (the role's and the check) run with: a database of its own, so
  a suite run in the workdir never drops another checkout's — or another run's — test database.
  """
  def task_env(task) do
    slug = String.replace(task.id, ~r/[^a-z0-9]+/i, "_")
    [{"TLON_TEST_DATABASE", "tlon_bench_#{slug}_#{System.unique_integer([:positive])}"}]
  end

  @doc "Drop the test database `task_env/1` named, once its run is over."
  def drop_database(env) do
    db = env |> List.keyfind("TLON_TEST_DATABASE", 0) |> elem(1)
    System.cmd("dropdb", ["--if-exists", db], stderr_to_stdout: true)
  end

  defp seed(repo, work) do
    File.cp_r!(repo, work)
    commit_fixture(work)
  end

  @doc """
  Seed `work` with the `server/` tree as of commit `sha` of this checkout, committed as the
  fixture. The deps' compiled build is copied in (a cold compile of them is minutes) but not the
  app's own: its beams would be newer than the snapshot's sources, and mix would trust them. The
  copy is private, so a check cannot recompile into the live `_build`; `deps/` is only read.
  """
  def seed_snapshot(sha, work) do
    root = Profiles.tlon_root()
    {_, 0} = System.cmd("sh", ["-c", ~s(git -C "$0" archive "$1" server | tar -x -C "$2"), root, sha, work])

    live = Path.join(root, "server")
    build = Path.join(work, "server/_build")
    File.mkdir_p!(build)
    File.cp_r!(Path.join(live, "_build/test"), Path.join(build, "test"))
    File.rm_rf!(Path.join(build, "test/lib/server"))
    File.ln_s!(Path.join(live, "deps"), Path.join(work, "server/deps"))
    commit_fixture(work)
  end

  defp commit_fixture(work) do
    git = &System.cmd("git", ["-c", "user.name=bench", "-c", "user.email=bench@localhost" | &1], cd: work)
    git.(["init", "-q"])
    git.(["add", "-A"])
    git.(["commit", "-qm", "fixture"])
  end

  # nothing on stdin (`pi -p` would wait on it), bounded by `timeout`; a harness launched from inside
  # a Claude Code session must not believe it is nested in one
  defp sh(argv, dir, timeout, merge?, env) do
    System.cmd("sh", ["-c", ~s(exec timeout "$0" "$@" </dev/null), to_string(timeout) | argv],
      cd: dir,
      stderr_to_stdout: merge?,
      env: [{"CLAUDECODE", nil}, {"CLAUDE_CODE_ENTRYPOINT", nil} | env]
    )
  end

  defp commit do
    case System.cmd("git", ["-C", Profiles.tlon_root(), "rev-parse", "--short", "HEAD"], stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp info(line), do: IO.puts(line)
end
