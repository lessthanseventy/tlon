defmodule Server.Bench.RolesTest do
  use ExUnit.Case, async: true

  alias Server.Bench.Roles

  defp tmp! do
    dir = Path.join(System.tmp_dir!(), "bench-roles-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  @tasks Path.join(Server.Profiles.tlon_root(), "bench/roles/tasks")
  # the senior set is real worklines, all `full`: the canary suite stays cheap
  @sets Roles.roles() |> Map.values() |> Enum.map(& &1.set) |> Enum.uniq() |> List.delete("senior")

  describe "the frozen fixtures" do
    test "every role's set has canary tasks, and full runs them all" do
      for set <- @sets do
        canary = Roles.load(@tasks, set, "canary")
        full = Roles.load(@tasks, set, "full")
        assert length(canary) >= 2, "#{set} has #{length(canary)} canary tasks"
        assert Enum.all?(canary, &(&1.tier == "canary"))
        assert MapSet.subset?(MapSet.new(canary, & &1.id), MapSet.new(full, & &1.id))
      end
    end

    test "every builder check fails on the untouched fixture — a check that cannot go red measures nothing" do
      tmp = tmp!()

      for t <- Roles.load(@tasks, "builder", "full") do
        work = Path.join(tmp, t.id)
        File.cp_r!(t.repo, work)
        File.cp_r!(Path.join(t.dir, "check"), work)
        {out, code} = System.cmd("sh", ["-c", t.grader["cmd"]], cd: work, stderr_to_stdout: true)
        assert code != 0, "#{t.id}'s check passed before any work:\n#{out}"
      end
    end

    test "a task.json without a valid grader is refused" do
      tmp = tmp!()
      dir = Path.join([tmp, "reviewer", "x1"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "prompt.md"), "review")
      File.write!(Path.join(dir, "task.json"), ~s({"tier": "canary", "grader": {"kind": "json", "expect": {}}}))
      assert_raise RuntimeError, ~r/bad task.json/, fn -> Roles.load(tmp, "reviewer", "canary") end
    end
  end

  describe "a task sourced from a commit" do
    test "builder-senior answers the senior set" do
      assert Roles.roles()["builder-senior"].set == "senior"
    end

    defp source_task!(source) do
      tmp = tmp!()
      dir = Path.join([tmp, "senior", "s0"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "prompt.md"), "build it")
      meta = %{"tier" => "full", "grader" => %{"kind" => "check", "cmd" => "true"}, "source" => source}
      File.write!(Path.join(dir, "task.json"), JSON.encode!(meta))
      tmp
    end

    test "loads with its commit and no repo" do
      tmp = source_task!(%{"commit" => "abc1234"})
      assert [%{source: "abc1234", repo: nil}] = Roles.load(tmp, "senior", "full")
    end

    test "a commit that is not a hex sha is refused" do
      tmp = source_task!(%{"commit" => "main"})
      assert_raise RuntimeError, ~r/bad task.json/, fn -> Roles.load(tmp, "senior", "full") end
    end
  end

  describe "grade_json/2" do
    @expect %{
      "verdict" => %{"equals" => "request_changes"},
      "findings" => %{"matches" => "workspace"},
      "stage" => %{"in" => ["plan", "build"]}
    }

    test "every expected key matches → pass; values compare trimmed and case-insensitively" do
      reply = """
      Looks wrong.

      ```json
      {"verdict": " Request_Changes", "findings": ["line 47 drops the Workspace scope"], "stage": "BUILD"}
      ```
      """

      assert %{passed: true, detail: "ok"} = Roles.grade_json(%{"expect" => @expect}, reply)
    end

    test "a miss names the key and what came back" do
      reply = ~s({"verdict": "approve", "findings": [], "stage": "spec"})
      assert %{passed: false, detail: detail} = Roles.grade_json(%{"expect" => @expect}, reply)
      assert detail =~ ~s(verdict="approve")
      assert detail =~ "findings=[]"
      assert detail =~ ~s(stage="spec")
    end

    test "the last fenced block wins over an earlier one; a reply without the keys fails" do
      reply = """
      ```json
      {"verdict": "approve", "findings": [], "stage": "plan"}
      ```
      On reflection:
      ```json
      {"verdict": "request_changes", "findings": ["unscoped by workspace"], "stage": "plan"}
      ```
      """

      assert %{passed: true} = Roles.grade_json(%{"expect" => @expect}, reply)
      assert %{passed: false, detail: "no JSON object" <> _} = Roles.grade_json(%{"expect" => @expect}, "I approve.")
    end
  end

  test "an expected null takes a JSON null, an empty string or the string null" do
    expect = %{"expect" => %{"lead" => %{"equals" => nil}, "q" => %{"in" => ["yu", nil]}}}
    assert %{passed: true} = Roles.grade_json(expect, ~s({"lead": null, "q": "Yu"}))
    assert %{passed: true} = Roles.grade_json(expect, ~s({"lead": "null", "q": ""}))
    assert %{passed: false} = Roles.grade_json(expect, ~s({"lead": "pierre", "q": null}))
  end

  test "grade_judged/2 averages the dimensions against the pass mark; a judge error fails" do
    judged = {:ok, %{scores: %{"a" => 4, "b" => 3}, rationale: "fine"}}
    assert %{passed: true, score: 3.5, detail: "fine"} = Roles.grade_judged(%{}, judged)
    assert %{passed: false} = Roles.grade_judged(%{"pass" => 4}, judged)
    assert %{passed: false, score: nil, detail: "judge failed" <> _} = Roles.grade_judged(%{}, {:error, :down})
  end

  describe "parse_output/2" do
    test "claude_code: the result object's reply, tokens and list cost" do
      out =
        ~s({"type":"result","result":"done","num_turns":3,"total_cost_usd":0.05,) <>
          ~s("usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":40}})

      assert {"done", %{input: 10, output: 20, cache_read: 300, cache_write: 40, cost_usd: 0.05, turns: 3}} =
               Roles.parse_output(:claude_code, out)
    end

    test "claude_code, no result (timeout): a message streamed per content block counts once, at its final output" do
      ev = fn id, out, text ->
        JSON.encode!(%{
          type: "assistant",
          message: %{
            id: id,
            content: [%{type: "text", text: text}],
            usage: %{input_tokens: 10, output_tokens: out, cache_read_input_tokens: 5, cache_creation_input_tokens: 1}
          }
        })
      end

      out = Enum.join([ev.("m1", 2, "a"), ev.("m1", 40, "b"), ev.("m2", 3, "c"), ev.("m2", 7, "d")], "\n")

      assert {"d", %{input: 20, output: 47, cache_read: 10, cache_write: 2, turns: 2}} =
               Roles.parse_output(:claude_code, out)
    end

    test "output that isn't the harness's JSON is the reply, with zero usage" do
      assert {"boom", %{input: 0, output: 0}} = Roles.parse_output(:claude_code, "boom")
    end
  end

  describe "the routing" do
    @archetypes %{reviewer: %{model: %{provider: "anthropic", model: "sonnet"}}, builder: %{model: :arch}}
    @grades %{"junior" => %{provider: "anthropic", model: "haiku"}, "senior" => %{provider: "x", model: "senior"}}

    test "override > grade > archetype > senior grade for an archetype not on this commit" do
      grade = &@grades[&1]
      assert Roles.model(%{archetype: :builder, grade: "junior"}, nil, @archetypes, grade).model == "haiku"
      assert Roles.model(%{archetype: :reviewer, grade: nil}, nil, @archetypes, grade).model == "sonnet"
      assert Roles.model(%{archetype: :librarian, grade: nil}, nil, @archetypes, grade).model == "senior"
      assert Roles.model(%{archetype: :builder, grade: "junior"}, %{model: "o"}, @archetypes, grade) == %{model: "o"}
    end

    test "parse_model/1 reads provider/model[:effort]" do
      assert {:ok, %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}} =
               Roles.parse_model("ollama-cloud/glm-5.2")

      assert {:ok, %{provider: "anthropic", model: "claude-haiku-5-5", thinking: "low"}} =
               Roles.parse_model("anthropic/claude-haiku-5-5:low")

      assert {:error, _} = Roles.parse_model("haiku")
    end
  end

  describe "argv/3" do
    defp profile(harness, model) do
      %Server.Profile{name: "bench-x", harness: harness, model: model, system_prompt: "You are bench-x."}
    end

    test "claude_code: the aside's flags, streamed JSON out, and the write tools only for a role that writes" do
      p = profile(:claude_code, %{provider: "anthropic", model: "claude-haiku-5-5", thinking: "low"})
      read = Roles.argv(p, "do it", false)
      write = Roles.argv(p, "do it", true)

      assert [_gateway, "anthropic", "claude", "-p", "do it" | _] = read
      assert read |> Enum.chunk_every(2, 1) |> Enum.member?(["--tools", "Read,Grep,Glob"])
      assert read |> Enum.chunk_every(2, 1) |> Enum.member?(["--output-format", "stream-json"])
      assert read |> Enum.chunk_every(2, 1) |> Enum.member?(["--effort", "low"])
      refute "--allowedTools" in read
      assert write |> Enum.chunk_every(2, 1) |> Enum.member?(["--tools", "Read,Grep,Glob,Edit,Write,Bash"])
      assert write |> Enum.chunk_every(2, 1) |> Enum.member?(["--allowedTools", "Edit,Write,Bash"])

      system = read |> Enum.drop_while(&(&1 != "--append-system-prompt")) |> Enum.at(1)
      assert system =~ "You are bench-x."
      assert system =~ "BENCH:"
    end

    test "an ollama model: its provider's endpoint, by its own name, the edit tools for a writer" do
      p = profile(:claude_code, %{provider: "ollama-cloud", model: "deepseek-v4.1-flash", thinking: "medium"})
      write = Roles.argv(p, "do it", true)

      assert [_gateway, "ollama-cloud", "claude" | _] = write
      assert write |> Enum.chunk_every(2, 1) |> Enum.member?(["--model", "deepseek-v4.1-flash"])
      assert write |> Enum.chunk_every(2, 1) |> Enum.member?(["--tools", "Read,Grep,Glob,Edit,Write,Bash"])
    end
  end

  describe "the record and the README" do
    defp result(tier, passed, opts \\ []) do
      %{
        id: "t",
        tier: tier,
        passed: passed,
        score: opts[:score],
        detail: "",
        wall_s: 1.25,
        usage: %{input: 10, output: 2, cache_read: 100, cache_write: 5, cost_usd: opts[:cost], turns: 1}
      }
    end

    test "record/2 tallies each tier, averages the rubric, sums wall time and usage" do
      r =
        Roles.record(%{role: "reviewer"}, [
          result("canary", true, cost: 0.01),
          result("canary", false, score: 3.0),
          result("full", true, score: 4.0, cost: 0.02)
        ])

      assert r.role == "reviewer"
      assert r.tiers == %{"canary" => %{passed: 1, total: 2}, "full" => %{passed: 1, total: 1}}
      assert r.rubric == 3.5
      assert r.wall_s == 3.8
      assert r.calls == 3
      assert r.usage == %{input: 345, output: 6, cost_usd: 0.03}
    end

    test "no judged task and no reported cost leave rubric and cost nil, not zero" do
      r = Roles.record(%{}, [result("canary", true)])
      assert r.rubric == nil
      assert r.usage.cost_usd == nil
      assert r.tiers == %{"canary" => %{passed: 1, total: 1}}
    end

    test "append!/2 grows the day's file; history/1 reads every day newest first; readme/1 renders it" do
      tmp = tmp!()

      meta = fn at, role ->
        Roles.record(
          %{
            role: role,
            model: "anthropic/claude-haiku-5-5",
            effort: "low",
            harness: :claude_code,
            commit: "abc1234",
            suite: "canary",
            started_at: at
          },
          [result("canary", true, cost: 0.004), result("canary", false)]
        )
      end

      Roles.append!(Path.join(tmp, "2026-10-08.json"), [meta.("2026-10-08T10:00:00Z", "reviewer")])
      Roles.append!(Path.join(tmp, "2026-10-09.json"), [meta.("2026-10-09T09:00:00Z", "qa")])
      Roles.append!(Path.join(tmp, "2026-10-09.json"), [meta.("2026-10-09T11:00:00Z", "planner")])

      assert ["planner", "qa", "reviewer"] = tmp |> Roles.history() |> Enum.map(& &1["role"])

      readme = tmp |> Roles.history() |> Roles.readme()
      rows = readme |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "| 2026"))

      assert [
               "| 2026-10-09 | planner | anthropic/claude-haiku-5-5 | low | claude_code | abc1234 | canary | 1/2 | – | – | 2.5s | 230/4 | $0.004 |",
               _,
               _
             ] = rows
    end
  end
end
