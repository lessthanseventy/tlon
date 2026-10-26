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

  describe "run/3 with a stubbed executor" do
    # exec.(dir, args, timeout_ms) -> {output, exit}; --out FILE is written the way the real task writes it
    defp exec(fps, runs) do
      fn dir, args, _ ->
        out = args |> Enum.chunk_every(2, 1, :discard) |> Enum.find_value(fn [k, v] -> k == "--out" && v end)
        side = if dir == "/main", do: :main, else: :branch

        body =
          if "--fingerprint" in args,
            do: fps[side],
            else: runs[{side, Enum.at(args, Enum.find_index(args, &(&1 == "--role")) + 1)}]

        File.write!(out, JSON.encode!(body))
        {"", 0}
      end
    end

    @fp %{"qa" => "a", "planner" => "a"}
    @dirs %{main: "/main", branch: "/b"}

    test "no steering path: nothing runs" do
      assert Contrast.run(["server/lib/server/thread.ex"], @dirs, exec: fn _, _, _ -> flunk("ran") end) == []
    end

    test "a skill or AGENTS.md alone is one unmeasurable row, nothing runs" do
      assert [%{kind: :unmeasurable, paths: ["AGENTS.md"]}] =
               Contrast.run(["AGENTS.md"], @dirs, exec: fn _, _, _ -> flunk("ran") end)
    end

    test "a profiles edit benches only the roles whose prompt moved, both sides" do
      ex =
        exec(%{main: @fp, branch: %{@fp | "qa" => "z"}}, %{
          {:main, "qa"} => [rec("m", 2, 3)],
          {:branch, "qa"} => [rec("b", 1, 3)]
        })

      assert [%{kind: :contrast, role: "qa", regression: true}] =
               Contrast.run(["server/lib/server/profiles.ex"], @dirs, exec: ex)
    end

    test "a main without --fingerprint is an error row, not a crash" do
      ex = fn _, _, _ -> {"unknown option", 1} end
      assert [%{kind: :error, why: why}] = Contrast.run(["server/lib/server/profiles.ex"], @dirs, exec: ex)
      assert why =~ "unknown option"
    end

    test "every call draws on the run's one wall; a side that hits it is an error row naming the wall" do
      me = self()

      ex = fn _, _, left ->
        send(me, {:left, left})
        {"", :timeout}
      end

      assert [%{kind: :error, why: why}] =
               Contrast.run(["server/lib/server/profiles.ex"], @dirs, exec: ex, wall_ms: 60_000)

      assert_received {:left, left}
      assert left in 1..60_000
      assert why =~ "wall"
    end

    test "a run whose wall is already spent never calls exec; each side is a not-run error row" do
      me = self()

      ex = fn _, _, _ ->
        send(me, :exec_called)
        {"", 0}
      end

      assert [%{kind: :error, why: why}] =
               Contrast.run(["server/lib/server/profiles.ex"], @dirs, exec: ex, wall_ms: 0)

      refute_received :exec_called
      assert why =~ "not run"
      assert why =~ "is spent"
    end

    test "roles over the cap are named skipped, after the rows that ran" do
      fps = %{main: %{}, branch: Map.new(~w(a b c d), &{&1, "x"})}
      runs = Map.new(for s <- [:main, :branch], r <- ~w(a b c), do: {{s, r}, [rec("c", 1, 1)]})
      rows = Contrast.run(["server/lib/server/profiles.ex"], @dirs, exec: exec(fps, runs))
      assert [%{role: "a"}, %{role: "b"}, %{role: "c"}, %{kind: :skipped, roles: ["d"]}] = rows
    end
  end

  describe "sh/3: one side as its own process group" do
    @describetag :tmp_dir

    test "output and exit come back", %{tmp_dir: tmp} do
      assert {"hi\n", 3} = Contrast.sh(["sh", "-c", "echo hi; exit 3"], tmp, 5_000)
    end

    test "past its timeout the whole group is killed, grandchildren included", %{tmp_dir: tmp} do
      pgid = Path.join(tmp, "pgid")
      assert {out, :timeout} = Contrast.sh(["sh", "-c", "echo $$ >#{pgid}; sleep 300 & echo started; wait"], tmp, 300)
      assert out =~ "started"
      assert group_gone?(pgid |> File.read!() |> String.trim())
    end

    defp group_gone?(pgid, tries \\ 20) do
      case System.cmd("pgrep", ["-g", pgid]) do
        {_, 1} -> true
        _ when tries > 0 -> Process.sleep(100) && group_gone?(pgid, tries - 1)
        {alive, _} -> flunk("still alive in group #{pgid}: #{alive}")
      end
    end
  end

  test "unmeasurable and skipped lines say why nothing was measured" do
    assert Contrast.line(Contrast.unmeasurable(["AGENTS.md"])) ==
             "bench_contrast unmeasurable: AGENTS.md — a seat reads it, the bench never loads it"

    assert Contrast.line(Contrast.skipped(["qa", "reviewer"])) ==
             "bench_contrast skipped: qa, reviewer — over the 3-role cap"
  end
end
