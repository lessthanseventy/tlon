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
    {out, 0} = System.cmd("bash", ["-c", @run, @script, output])

    String.split(out, "\n", trim: true)
  end

  test "ExUnit: each failing test by name, with its file:line" do
    assert failures(@exunit) == [
             "1) test greets the world (DemoTest) — test/demo_test.exs:3",
             "2) doctest Demo.hello/0 (1) (DemoTest) — test/demo_test.exs:2"
           ]
  end

  test "bun: each (fail) line" do
    assert failures(@bun) == ["(fail) the clock reads 404 [0.90ms]"]
  end

  test "a green run names nothing" do
    assert failures("Finished in 0.1 seconds\nResult: 3/3 passed\n") == []
  end

  test "bounded: at most 10 names, none over 160 characters" do
    many = Enum.map_join(1..15, "\n", &"(fail) #{&1} #{String.duplicate("x", 300)}")
    names = failures(many)
    assert length(names) == 10
    assert Enum.all?(names, &(String.length(&1) <= 160))
  end
end
