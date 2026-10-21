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

      sh.(repo, """
      git config user.email t@t && git config user.name t && git add -A && git commit -qm one && git branch -M main &&
      git push -q origin main && git checkout -qb land/feature && echo f >f && git add f && git commit -qm f &&
      git checkout -q main
      """)

      File.write!(Path.join(tmp, "bin/mise"), ~S"""
      #!/bin/sh
      [ "$1" = run ] || exit 0
      echo "$(git rev-parse HEAD) $CHECKS_LABEL ${TLON_TEST_DATABASE:-}" >"$GATE_LOG"
      echo "$PWD" >"$GATE_LOG.cwd"
      [ -z "$GATE_NOISE" ] || { echo "the failing assertion, line 42"; seq 1 2000; }
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
          {"XDG_CACHE_HOME", Path.join(ctx.tmp, "cache")},
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
