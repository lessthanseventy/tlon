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

  @timeout_s %{"builder" => 900}
  @default_timeout_s 300
  @check_timeout_s 300
  @source_check_timeout_s 900

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
    if task.source, do: seed_source(Profiles.tlon_root(), task.source, work)

    t0 = System.monotonic_time(:millisecond)
    timeout = Map.get(@timeout_s, task.set, @default_timeout_s)
    {out, code} = sh(Roles.argv(profile, task.prompt, !!(task.repo || task.source)), work, timeout, false)
    wall = (System.monotonic_time(:millisecond) - t0) / 1000
    {reply, usage} = Roles.parse_output(profile.harness, out)

    grade = grade(task, reply, work, judge)
    File.rm_rf!(work)

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

  defp grade(%{grader: %{"kind" => "json"} = g}, reply, _work, _judge), do: Roles.grade_json(g, reply)

  defp grade(%{grader: %{"kind" => "judge"} = g} = task, reply, _work, judge),
    do: Roles.grade_judged(g, judge.score(Roles.judge_prompt(g, task.prompt, reply)))

  defp grade(%{grader: %{"kind" => "check", "cmd" => cmd}} = task, _reply, work, _judge) do
    hidden = Path.join(task.dir, "check")
    if File.dir?(hidden), do: File.cp_r!(hidden, work)
    check_timeout = if task.source, do: @source_check_timeout_s, else: @check_timeout_s
    {out, code} = sh(["sh", "-c", cmd], work, check_timeout, true)
    detail = if code == 0, do: "ok", else: "check exit #{code}: " <> (out |> String.trim() |> String.slice(-300, 300))
    %{passed: code == 0, score: nil, detail: detail}
  end

  defp seed(repo, work) do
    File.cp_r!(repo, work)
    commit_fixture(work)
  end

  @doc """
  Seed `work` with `server/` as it was at the parent of `sha` in the repo at `root` (the state the
  real workline started from), plus the live `_build` so a task compiles incrementally; committed as
  the fixture.
  """
  def seed_source(root, sha, work) do
    {_, 0} =
      System.cmd("sh", ["-c", ~s(git -C "$0" archive "$1^" server | tar -x -C "$2"), root, sha, work])

    build = Path.join(root, "server/_build")
    if File.dir?(build), do: System.cmd("cp", ["-r", "--reflink=auto", build, Path.join(work, "server/_build")])
    commit_fixture(work)
  end

  @doc "What the real workline changed under `server/` except its tests (which stay hidden), as a patch."
  def reference_patch(root, sha) do
    {patch, 0} =
      System.cmd("git", ["-C", root, "diff", "#{sha}^", sha, "--", "server", ":(exclude)server/test"])

    patch
  end

  @doc "Apply the real workline's non-test change to `work`: what a model that solved the task would leave."
  def apply_reference(root, sha, work) do
    patch = Path.join(work, ".reference.patch")
    File.write!(patch, reference_patch(root, sha))
    {_, 0} = System.cmd("git", ["apply", ".reference.patch"], cd: work, stderr_to_stdout: true)
    File.rm!(patch)
    :ok
  end

  @doc """
  Grade every sourced task of `role`'s set with the real solution applied instead of a model: proves
  each fixture is green on the reference. Returns `[{task, grade}]`; spends no model quota.
  """
  def oracle(suite, role, opts \\ []) do
    dir = opts[:dir] || Path.join(Profiles.tlon_root(), "bench/roles")
    root = Profiles.tlon_root()

    for task <- Path.join(dir, "tasks") |> Roles.load(Roles.roles()[role].set, suite), task.source do
      work = Path.join(System.tmp_dir!(), "tlon-oracle-#{task.id}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(work)
      seed_source(root, task.source, work)
      apply_reference(root, task.source, work)
      grade = grade(task, nil, work, nil)
      File.rm_rf!(work)
      {task, grade}
    end
  end

  defp commit_fixture(work) do
    git = &System.cmd("git", ["-c", "user.name=bench", "-c", "user.email=bench@localhost" | &1], cd: work)
    git.(["init", "-q"])
    git.(["add", "-A"])
    git.(["commit", "-qm", "fixture"])
  end

  # nothing on stdin (`pi -p` would wait on it), bounded by `timeout`; a harness launched from inside
  # a Claude Code session must not believe it is nested in one
  defp sh(argv, dir, timeout, merge?) do
    System.cmd("sh", ["-c", ~s(exec timeout "$0" "$@" </dev/null), to_string(timeout) | argv],
      cd: dir,
      stderr_to_stdout: merge?,
      env: [{"CLAUDECODE", nil}, {"CLAUDE_CODE_ENTRYPOINT", nil}]
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
