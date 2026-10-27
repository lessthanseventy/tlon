defmodule Server.WorklineVerifyScriptTest do
  # scripts/workline-verify.sh's failures(): the failing tests by name, read out of a real
  # ExUnit and a real bun run — what a red verify and a bounced landing lead with.
  use ExUnit.Case, async: true

  @script Path.expand("../../../scripts/workline-verify.sh", __DIR__)

  @exunit """
  Running ExUnit with seed: 546401, max_cases: 40

    1) test greets the world (DemoTest)
       test/demo_test.exs:3
       Assertion with == failed
       code:  assert Demo.hello() == :earth
       left:  :world
       right: :earth
       stacktrace:
         test/demo_test.exs:3: (test)

    2) doctest Demo.hello/0 (1) (DemoTest)
       test/demo_test.exs:2
       Doctest failed

  .
  Finished in 0.09 seconds (0.00s async, 0.09s sync)

  Result: 1/3 passed
  Failed: 2 tests
  """

  @bun """
  b.test.ts:
  2 | test("the clock reads 404", () => { expect(1).toBe(2); });
  error: expect(received).toBe(expected)

  Expected: 2
  Received: 1

  (fail) the clock reads 404 [0.90ms]

   1 pass
   1 fail
  """

  # the script's own function, lifted out and fed `output` on stdin
  @run ~S"""
  eval "$(sed -n '/^failures() {/,/^}/p' "$0")"
  printf '%s\n' "$1" | failures
  """

  # the script's strays(), lifted out: `git diff --name-status --no-renames` lines on stdin
  @strays ~S"""
  eval "$(sed -n '/^strays() {/,/^}/p' "$0")"
  printf '%s' "$2" | strays "$1"
  """

  # the script's copy_deps(), lifted out: a tree's deps dir copied into a fresh checkout
  @copy ~S"""
  eval "$(sed -n '/^copy_deps() {/,/^}/p' "$0")"
  copy_deps "$1" "$2" "$3"
  """

  defp failures(output) do
    # the service runs with no LANG: the C locale, where tools count bytes, not characters
    {out, 0} = System.cmd("bash", ["-c", @run, @script, output], env: [{"LC_ALL", "C"}, {"LANG", nil}])

    String.split(out, "\n", trim: true)
  end

  test "ExUnit: each failing test by name, with its file:line" do
    assert failures(@exunit) == [
             "1) test greets the world (DemoTest) — test/demo_test.exs:3",
             "2) doctest Demo.hello/0 (1) (DemoTest) — test/demo_test.exs:2"
           ]
  end

  test "through mise, which prefixes every line with its task: the names still come out, unprefixed" do
    prefixed = @exunit |> String.split("\n") |> Enum.map_join("\n", &"[test:elixir] #{&1}")

    assert failures(prefixed) == [
             "1) test greets the world (DemoTest) — test/demo_test.exs:3",
             "2) doctest Demo.hello/0 (1) (DemoTest) — test/demo_test.exs:2"
           ]

    assert failures("[office:check] (fail) the clock reads 404 [0.90ms]") == ["(fail) the clock reads 404 [0.90ms]"]
  end

  test "bun: each (fail) line, after the error: line that says why" do
    assert failures(@bun) == ["error: expect(received).toBe(expected)", "(fail) the clock reads 404 [0.90ms]"]
  end

  test "bun through mise, interleaved with another task's compile noise: the error: line still comes out" do
    interleaved = """
    [office:check] refresh.test.ts:
    [server:check] ==> jason
    [server:check] Compiling 10 files (.ex)
    [office:check] error: the pane never showed the step: mise ERROR Config files in ~/office/mise.toml are not trusted.
    [server:check] Generated jason app
    [office:check] (fail) refresh > a step reaches the pane [5002.11ms]
    """

    assert failures(interleaved) == [
             "error: the pane never showed the step: mise ERROR Config files in ~/office/mise.toml are not trusted.",
             "(fail) refresh > a step reaches the pane [5002.11ms]"
           ]
  end

  test "a green run names nothing, not even an error: line no test failed on" do
    assert failures("error: a logged one\nFinished in 0.1 seconds\nResult: 3/3 passed\n") == []
  end

  test "a cut never splits a multibyte character: the names stay valid UTF-8" do
    [name] = failures("(fail) " <> String.duplicate("é—", 120))
    assert String.valid?(name)
  end

  test "bounded: at most 10 names, none over 160 characters" do
    many = Enum.map_join(1..15, "\n", &"(fail) #{&1} #{String.duplicate("x", 300)}")
    names = failures(many)
    assert length(names) == 10
    assert Enum.all?(names, &(String.length(&1) <= 160))
  end

  defp strays(slug, name_status) do
    {out, 0} = System.cmd("bash", ["-c", @strays, @script, slug, name_status])
    String.split(out, "\n", trim: true)
  end

  describe "strays: what a workline's diff may not touch" do
    test "a new file at the repo root is a stray; an existing root file changed is not" do
      assert strays("demo", "A\tpr.md\nM\tmise.toml\nM\tAGENTS.md\nD\tREADME.md\n") == ["pr.md"]
    end

    test "another workline's work/<slug>/ is a stray; its own is not" do
      diff = "A\twork/demo/pr.md\nM\twork/demo/review.md\nA\twork/other/pr.md\nM\twork/demo-two/plan.md\n"
      assert strays("demo", diff) == ["work/other/pr.md", "work/demo-two/plan.md"]
    end

    test "code anywhere under a directory is not a stray" do
      diff =
        "A\tserver/lib/server/x.ex\nM\toffice/src/a.ts\nA\tscripts/new.sh\nA\tdocs/plans/p.md\nM\ttasks/server.toml\n"

      assert strays("demo", diff) == []
    end
  end

  describe "branch mode: a PR's landing gate (LAND_REF, thread `-`)" do
    @describetag :tmp_dir

    # a repo with a bare origin and a private land/feature ref one commit past main; mise stubbed to
    # record where the gate ran and under what label, exiting FAKE_GATE
    setup %{tmp_dir: tmp} do
      sh = fn cwd, cmd ->
        {out, 0} = System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true)
        String.trim(out)
      end

      sh.(tmp, "git init -q --bare origin.git && git clone -q origin.git tlon && mkdir bin")
      repo = Path.join(tmp, "tlon")
      File.mkdir_p!(Path.join(repo, "scripts"))

      File.mkdir_p!(Path.join(repo, "scripts/lib"))

      for s <- ~w(workline-verify.sh git-fetch-origin.sh lib/seed-hex.sh),
          do: File.cp!(Path.join(Path.dirname(@script), s), Path.join(repo, "scripts/#{s}"))

      # the CLI the script records and advances through, in a workline's verify: every call logged
      File.write!(Path.join(repo, "scripts/tlon-cli.sh"), ~S"""
      #!/bin/sh
      printf '%s\n' "$*" >>"$CLI_LOG"
      """)

      File.chmod!(Path.join(repo, "scripts/tlon-cli.sh"), 0o755)

      sh.(repo, """
      git config user.email t@t && git config user.name t && git add -A && git commit -qm one && git branch -M main &&
      git push -q origin main && git checkout -qb land/feature && echo f >f && git add f && git commit -qm f &&
      git checkout -q main
      """)

      File.write!(Path.join(tmp, "bin/mise"), ~S"""
      #!/bin/sh
      # exec: the canary A/B task, printing CONTRAST_OUT (with mix's compile noise) when set; the
      # --main dir it was handed and that dir's HEAD, as seen while it runs
      [ "$1" = exec ] && {
        echo "$*" >>"$GATE_LOG.exec"
        while [ $# -gt 1 ]; do [ "$1" = --main ] && echo "$2 $(git -C "$2" rev-parse HEAD)" >>"$GATE_LOG.main"; shift; done
        [ -z "${CONTRAST_OUT:-}" ] || { echo "Compiling 2 files (.ex)"; cat "$CONTRAST_OUT"; }
        exit 0
      }
      [ "$1" = run ] || exit 0
      echo "$(git rev-parse HEAD) $CHECKS_LABEL ${TLON_TEST_DATABASE:-}" >"$GATE_LOG"
      echo "$PWD" >"$GATE_LOG.cwd"
      echo "$*" >"$GATE_LOG.args"
      [ -z "$GATE_NOISE" ] || { echo "the failing assertion, line 42"; seq 1 2000; }
      exit "${FAKE_GATE:-0}"
      """)

      File.chmod!(Path.join(tmp, "bin/mise"), 0o755)
      %{tmp: tmp, repo: repo, ref: sh.(repo, "git rev-parse land/feature"), main: sh.(repo, "git rev-parse main")}
    end

    defp gate(ctx, env \\ []) do
      env =
        [
          {"PATH", "#{ctx.tmp}/bin:#{System.get_env("PATH")}"},
          {"TMPDIR", ctx.tmp},
          {"XDG_CACHE_HOME", Path.join(ctx.tmp, "cache")},
          {"GATE_LOG", Path.join(ctx.tmp, "gate.log")},
          {"WORKLINE_GATE", "1"},
          {"LAND_REF", "land/feature"},
          {"CHECKS_LABEL", "PR #7 landing feature"},
          {"RUN_TASK", nil}
        ] ++ env

      System.cmd("bash", [Path.join(ctx.repo, "scripts/workline-verify.sh"), "-", "pr-7-feature", ctx.repo],
        env: env,
        stderr_to_stdout: true
      )
    end

    # a workline's own verify (thread 7, work/pr-7-feature): records through the CLI stub and advances.
    # Branch mode's variables are cleared: under run_task the suite inherits the job's own (#620).
    defp verify(ctx, env \\ []) do
      env =
        [
          {"WORKLINE_GATE", nil},
          {"LAND_REF", nil},
          {"RUN_TASK", nil},
          {"RULES_ONLY", nil},
          {"CHECKS_LABEL", nil},
          {"PATH", "#{ctx.tmp}/bin:#{System.get_env("PATH")}"},
          {"TMPDIR", ctx.tmp},
          {"XDG_CACHE_HOME", Path.join(ctx.tmp, "cache")},
          {"GATE_LOG", Path.join(ctx.tmp, "gate.log")},
          {"CLI_LOG", Path.join(ctx.tmp, "cli.log")}
        ] ++ env

      System.cmd("bash", [Path.join(ctx.repo, "scripts/workline-verify.sh"), "7", "pr-7-feature", ctx.repo],
        env: env,
        stderr_to_stdout: true
      )
    end

    # the workline's branch, one commit past main: `files` (path => content) under server/
    defp workline!(ctx, files) do
      writes = Enum.map_join(files, " && ", fn {p, c} -> "mkdir -p #{Path.dirname(p)} && echo '#{c}' >#{p}" end)

      {_, 0} =
        System.cmd(
          "sh",
          [
            "-c",
            "git checkout -qb work/pr-7-feature main && #{writes} && git add -A && git commit -qm w && git checkout -q main"
          ],
          cd: ctx.repo
        )
    end

    @task_file "server/lib/mix/tasks/server.bench_contrast.ex"

    test "canary A/B: a tree without the task runs none; a run that prints no row records and notes nothing", ctx do
      workline!(ctx, %{"server/x.ex" => "x"})
      assert {_, 0} = verify(ctx)
      refute File.exists?(Path.join(ctx.tmp, "gate.log.exec"))
      cli = File.read!(Path.join(ctx.tmp, "cli.log"))
      refute cli =~ "bench_contrast"
      refute cli =~ "\nnote "
      assert cli |> String.trim() |> String.split("\n") |> List.last() == "advance 7 verify"
    end

    test "canary A/B: a tree with the task but no steering: it runs, prints nothing, nothing is recorded", ctx do
      workline!(ctx, %{@task_file => "t"})
      assert {_, 0} = verify(ctx)
      assert File.read!(Path.join(ctx.tmp, "gate.log.exec")) =~ "mix server.bench_contrast --branch "
      refute File.read!(Path.join(ctx.tmp, "cli.log")) =~ "bench_contrast"
    end

    test "canary A/B: each row is a bench_contrast CHECKS row (exit 0) and one note, before the advance; mix's noise is not",
         ctx do
      workline!(ctx, %{@task_file => "t"})
      rows = Path.join(ctx.tmp, "rows")

      File.write!(rows, """
      bench_contrast qa: main 2/2 · branch 1/2 · tokens 10/12 · turns 6/8 · m1..b1 · REGRESSION
      bench_contrast unmeasurable: AGENTS.md — a seat reads it, the bench never loads it
      """)

      assert {_, 0} = verify(ctx, [{"CONTRAST_OUT", rows}])

      log = ctx.tmp |> Path.join("cli.log") |> File.read!()
      # the gate's row, one row per line, the note (its body repeats the rows), the advance
      [_gate, qa, agents, note, body1, body2, advance] = String.split(log, "\n", trim: true)

      assert qa ==
               "record-verify 7 pr-7-feature 0 bench_contrast bench_contrast qa: main 2/2 · branch 1/2 · tokens 10/12 · turns 6/8 · m1..b1 · REGRESSION"

      assert agents =~ "record-verify 7 pr-7-feature 0 bench_contrast bench_contrast unmeasurable: AGENTS.md"
      assert note =~ "note 7 verify: canary A/B"
      assert body1 =~ "REGRESSION" and body2 =~ "unmeasurable: AGENTS.md"
      refute log =~ "Compiling"
      assert advance == "advance 7 verify"
    end

    test "canary A/B: main's side is a throwaway worktree of origin/main under the verify cache, never the root checkout, gone after",
         ctx do
      workline!(ctx, %{@task_file => "t"})
      assert {_, 0} = verify(ctx)
      [main] = ctx.tmp |> Path.join("gate.log.main") |> File.read!() |> String.split("\n", trim: true)
      [dir, head] = String.split(main, " ")
      refute dir == ctx.repo
      assert String.starts_with?(dir, Path.join(ctx.tmp, "cache/tlon-verify/main-"))
      assert head == ctx.main
      refute File.exists?(dir)
      {list, 0} = System.cmd("git", ["-C", ctx.repo, "worktree", "list"])
      assert [_repo_itself] = String.split(list, "\n", trim: true)
    end

    test "canary A/B: a red gate runs no canary", ctx do
      workline!(ctx, %{@task_file => "t"})
      assert {_, _} = verify(ctx, [{"FAKE_GATE", "1"}, {"CONTRAST_OUT", Path.join(ctx.tmp, "nowhere")}])
      refute File.exists?(Path.join(ctx.tmp, "gate.log.exec"))
    end

    test "green: the full check runs on the ref, named as the PR on the rack, and nothing is recorded", ctx do
      assert {out, 0} = gate(ctx)
      assert File.read!(Path.join(ctx.tmp, "gate.log")) =~ "#{ctx.ref} PR #7 landing feature tlon_land_pr_7_feature"
      refute out =~ "could not record"
    end

    # a verify train (Server.VerifyTrain) checks the stacked cars once; each car's own rules run first
    test "RULES_ONLY: a workline's own rules, then exit before the suite", ctx do
      sh = fn cmd -> {_, 0} = System.cmd("sh", ["-c", cmd], cd: ctx.repo, stderr_to_stdout: true) end

      sh.(
        "git checkout -qb work/pr-7-feature main && mkdir -p work/pr-7-feature && echo s >work/pr-7-feature/spec.md && " <>
          "git add work && git commit -qm spec && git push -q origin main && git checkout -q main"
      )

      env = [{"LAND_REF", nil}, {"RULES_ONLY", "1"}]

      assert {_, 0} = gate(ctx, env)
      refute File.exists?(Path.join(ctx.tmp, "gate.log"))

      sh.(
        "git checkout -q work/pr-7-feature && echo x >ROOTFILE && git add ROOTFILE && git commit -qm stray && git checkout -q main"
      )

      assert {out, 1} = gate(ctx, env)
      assert out =~ "ROOTFILE"
      refute File.exists?(Path.join(ctx.tmp, "gate.log"))
    end

    test "RUN_TASK names the mise task to run in place of the full check", ctx do
      assert {_, 0} = gate(ctx)
      assert File.read!(Path.join(ctx.tmp, "gate.log.args")) == "run check\n"

      assert {_, 0} = gate(ctx, [{"RUN_TASK", "office:test"}])
      assert File.read!(Path.join(ctx.tmp, "gate.log.args")) == "run office:test\n"
    end

    test "the checkout lives under the verify cache, never under TMPDIR (a seat's write root)", ctx do
      assert {_, 0} = gate(ctx)
      cwd = ctx.tmp |> Path.join("gate.log.cwd") |> File.read!() |> String.trim()
      assert String.starts_with?(cwd, Path.join(ctx.tmp, "cache/tlon-verify") <> "/")
    end

    test "red: exit 1 and the gate's tail on stdout, still nothing recorded", ctx do
      assert {out, 1} = gate(ctx, [{"FAKE_GATE", "1"}])
      refute out =~ "could not record"
    end

    test "red: the full log is kept and its path is in the evidence", ctx do
      assert {out, 1} = gate(ctx, [{"FAKE_GATE", "1"}, {"GATE_NOISE", "1"}])
      log = Path.join(ctx.repo, ".logs/verify-pr-7-feature.log")
      assert out =~ "(the full log: #{log})"
      refute out =~ "the failing assertion, line 42"
      assert File.read!(log) =~ "the failing assertion, line 42"
    end

    test "green: no log is kept", ctx do
      assert {_, 0} = gate(ctx, [{"GATE_NOISE", "1"}])
      refute File.exists?(Path.join(ctx.repo, ".logs"))
    end

    test "a verify already running holds the gate until it is done: a gate never passes on a run it didn't make", ctx do
      lock = Path.join(ctx.repo, ".git/workline-verify-pr-7-feature.lock")
      Port.open({:spawn_executable, System.find_executable("flock")}, [:binary, args: [lock, "sleep", "1"]])
      Process.sleep(200)

      assert {_, 0} = gate(ctx)
      assert File.exists?(Path.join(ctx.tmp, "gate.log"))
    end

    test "its rebase onto main moves no branch, whatever rebase.updateRefs says", ctx do
      {_, 0} =
        System.cmd(
          "sh",
          [
            "-c",
            "git branch keep land/feature && echo m >m && git add m && git commit -qm m && git push -q origin main"
          ],
          cd: ctx.repo
        )

      before = ctx.ref

      assert {_, 0} =
               gate(ctx, [
                 {"GIT_CONFIG_COUNT", "1"},
                 {"GIT_CONFIG_KEY_0", "rebase.updateRefs"},
                 {"GIT_CONFIG_VALUE_0", "true"}
               ])

      {after_keep, 0} = System.cmd("git", ["rev-parse", "keep"], cd: ctx.repo)
      assert String.trim(after_keep) == before
    end

    test "a rebase conflict is recorded as the branch's red, not retried: check_failed cmd rebase, exit 1, nothing advanced",
         ctx do
      {_, 0} =
        System.cmd(
          "sh",
          [
            "-c",
            "git checkout -qb work/pr-7-feature main && echo mine >c && git add c && git commit -qm mine && " <>
              "git checkout -q main && echo theirs >c && git add c && git commit -qm theirs && git push -q origin main"
          ],
          cd: ctx.repo
        )

      assert {_, 1} = verify(ctx)

      cli = File.read!(Path.join(ctx.tmp, "cli.log"))
      assert cli =~ ~r/^record-verify 7 pr-7-feature 1 rebase c$/m
      refute cli =~ ~r/^note /m
      refute cli =~ ~r/^advance /m
    end
  end

  # scripts/lib/seed-hex.sh, which every gate sources: `seed_hex_home <src> <dest>`
  @seed ~S"""
  . "$0"
  seed_hex_home "$1" "$2"
  """

  @seed_lib Path.expand("../../../scripts/lib/seed-hex.sh", __DIR__)

  defp seed_hex_home(src, dest), do: System.cmd("bash", ["-c", @seed, @seed_lib, src, dest], stderr_to_stdout: true)

  describe "seed_hex_home: the gate's own Hex home" do
    @tag :tmp_dir
    test "carries the user's config (repo keys, tokens) and registry cache, not the package tarballs", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src")
      File.mkdir_p!(Path.join(src, "packages/hexpm"))
      File.write!(Path.join(src, "hex.config"), "{unsafe_https,<<\"true\">>}.\n")
      File.write!(Path.join(src, "cache.ets"), "ets")
      File.write!(Path.join(src, "packages/hexpm/jason-1.4.4.tar"), "tar")
      dest = Path.join(tmp, "dest")

      assert {_, 0} = seed_hex_home(src, dest)
      assert File.read!(Path.join(dest, "hex.config")) == "{unsafe_https,<<\"true\">>}.\n"
      assert File.read!(Path.join(dest, "cache.ets")) == "ets"
      refute File.exists?(Path.join(dest, "packages"))
    end

    @tag :tmp_dir
    test "a machine with no Hex home yet still gets an empty one of its own", %{tmp_dir: tmp} do
      dest = Path.join(tmp, "dest")
      assert {_, 0} = seed_hex_home(Path.join(tmp, "nowhere"), dest)
      assert File.ls!(dest) == []
    end

    @tag :tmp_dir
    test "a config caught mid-rewrite (empty) is never seeded blank", %{tmp_dir: tmp} do
      src = Path.join(tmp, "src")
      File.mkdir_p!(src)
      File.write!(Path.join(src, "hex.config"), "")
      File.write!(Path.join(src, "cache.ets"), "ets")
      dest = Path.join(tmp, "dest")

      assert {_, 0} = seed_hex_home(src, dest)
      refute File.exists?(Path.join(dest, "hex.config"))
      assert File.read!(Path.join(dest, "cache.ets")) == "ets"
    end
  end

  @tag :tmp_dir
  test "a deps dir that is a symlink into a shared one is copied, never linked", %{tmp_dir: tmp} do
    shared = Path.join(tmp, "shared/deps")
    File.mkdir_p!(Path.join(shared, "jason"))
    File.write!(Path.join(shared, "jason/x"), "shared\n")

    tree = Path.join(tmp, "tree")
    File.mkdir_p!(Path.join(tree, "server"))
    File.ln_s!(shared, Path.join(tree, "server/deps"))

    fresh = Path.join(tmp, "fresh")
    File.mkdir_p!(Path.join(fresh, "server"))

    assert {_, 0} = System.cmd("bash", ["-c", @copy, @script, tree, fresh, "server"])

    assert {:error, :einval} = File.read_link(Path.join(fresh, "server/deps"))
    File.write!(Path.join(fresh, "server/deps/jason/x"), "rebuilt\n")
    assert File.read!(Path.join(shared, "jason/x")) == "shared\n"
  end
end
