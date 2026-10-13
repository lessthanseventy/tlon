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
