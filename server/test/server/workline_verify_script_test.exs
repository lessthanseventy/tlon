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

  test "bun: each (fail) line" do
    assert failures(@bun) == ["(fail) the clock reads 404 [0.90ms]"]
  end

  test "a green run names nothing" do
    assert failures("Finished in 0.1 seconds\nResult: 3/3 passed\n") == []
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

      for s <- ~w(workline-verify.sh git-fetch-origin.sh),
          do: File.cp!(Path.join(Path.dirname(@script), s), Path.join(repo, "scripts/#{s}"))

      sh.(repo, """
      git config user.email t@t && git config user.name t && git add -A && git commit -qm one && git branch -M main &&
      git push -q origin main && git checkout -qb land/feature && echo f >f && git add f && git commit -qm f &&
      git checkout -q main
      """)

      File.write!(Path.join(tmp, "bin/mise"), ~S"""
      #!/bin/sh
      [ "$1" = run ] || exit 0
      echo "$(git rev-parse HEAD) $CHECKS_LABEL ${TLON_TEST_DATABASE:-}" >"$GATE_LOG"
      exit "${FAKE_GATE:-0}"
      """)

      File.chmod!(Path.join(tmp, "bin/mise"), 0o755)
      %{tmp: tmp, repo: repo, ref: sh.(repo, "git rev-parse land/feature")}
    end

    defp gate(ctx, env \\ []) do
      env =
        [
          {"PATH", "#{ctx.tmp}/bin:#{System.get_env("PATH")}"},
          {"TMPDIR", ctx.tmp},
          {"GATE_LOG", Path.join(ctx.tmp, "gate.log")},
          {"WORKLINE_GATE", "1"},
          {"LAND_REF", "land/feature"},
          {"CHECKS_LABEL", "PR #7 landing feature"}
        ] ++ env

      System.cmd("bash", [Path.join(ctx.repo, "scripts/workline-verify.sh"), "-", "pr-7-feature", ctx.repo],
        env: env,
        stderr_to_stdout: true
      )
    end

    test "green: the full check runs on the ref, named as the PR on the rack, and nothing is recorded", ctx do
      assert {out, 0} = gate(ctx)
      assert File.read!(Path.join(ctx.tmp, "gate.log")) =~ "#{ctx.ref} PR #7 landing feature tlon_land_pr_7_feature"
      refute out =~ "could not record"
    end

    test "red: exit 1 and the gate's tail on stdout, still nothing recorded", ctx do
      assert {out, 1} = gate(ctx, [{"FAKE_GATE", "1"}])
      refute out =~ "could not record"
    end
  end

  # the script's seed_hex_home(), lifted out: `seed_hex_home <src> <dest>`
  @seed ~S"""
  eval "$(sed -n '/^seed_hex_home() {/,/^}/p' "$0")"
  seed_hex_home "$1" "$2"
  """

  defp seed_hex_home(src, dest), do: System.cmd("bash", ["-c", @seed, @script, src, dest], stderr_to_stdout: true)

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
  end
end
