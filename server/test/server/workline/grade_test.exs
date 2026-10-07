defmodule Server.Workline.GradeTest do
  use ExUnit.Case, async: false

  alias Server.Workline
  alias Server.Workline.Grade

  @low %{"scope" => 1, "reversibility" => 1, "blast" => 2, "detectability" => 1, "proof" => 2}

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp change(attrs \\ %{}), do: Map.merge(%{paths: ["office/kit/pets.ts"], deleted: [], lines: 40, diff: "+x"}, attrs)

  describe "limits — read off the change, never the grader's call" do
    test "a plain office change hits none" do
      assert Grade.limits(change()) == []
    end

    test "each limit names itself" do
      for {attrs, named} <- [
            {%{paths: ["server/priv/repo/migrations/20261007_x.exs"]}, "migration"},
            {%{paths: ["server/mix.lock"]}, "dependency"},
            {%{paths: ["office/package.json"]}, "dependency"},
            {%{paths: [".github/workflows/ci.yml"]}, "CI"},
            {%{paths: ["scripts/workline-verify.sh"]}, "gate"},
            {%{paths: ["tasks/server.toml"]}, "gate"},
            {%{paths: ["office/AGENTS.md"]}, "law"},
            {%{paths: ["server/docs/spec.md"]}, "law"},
            {%{deleted: ["server/test/server/x_test.exs"]}, "deleted test"},
            {%{deleted: ["office/test/pets.test.ts"]}, "deleted test"},
            {%{lines: 401}, "too big"}
          ] do
        assert [reason] = Grade.limits(change(attrs)), "expected one limit for #{inspect(attrs)}"
        assert reason =~ named
      end
    end

    test "a deleted non-test file is no limit" do
      assert Grade.limits(change(%{deleted: ["office/kit/old.ts"]})) == []
    end
  end

  describe "parse" do
    test "the object, out of whatever prose or fence surrounds it" do
      text =
        ~s(Here you go:\n```json\n{"scores": #{Jason.encode!(@low)}, "reasons": {"blast": "pets only"}, "decisions": []}\n```)

      assert {:ok, %{"scores" => @low, "reasons" => %{"blast" => "pets only"}, "decisions" => []}} = Grade.parse(text)
    end

    test "an axis missing or out of range is not a grade" do
      assert {:error, why} = Grade.parse(~s({"scores": {"scope": 1}}))
      assert why =~ "not a grade"
      assert {:error, _} = Grade.parse(~s({"scores": #{Jason.encode!(%{@low | "blast" => 9})}}))
      assert {:error, _} = Grade.parse("I think it's fine")
    end
  end

  describe "allows?" do
    test "every axis at or under the threshold, no limit, nothing left to decide" do
      grade = %{"limits" => [], "decisions" => [], "scores" => @low}
      assert Grade.allows?(grade, 2)
      refute Grade.allows?(grade, 1)
      refute Grade.allows?(%{grade | "decisions" => ["what the pet says"]}, 5)
      refute Grade.allows?(%{"limits" => ["a database migration"]}, 5)
      refute Grade.allows?(nil, 5)
    end
  end

  test "the card line: every axis, the worst one's reason, what it leaves you" do
    line =
      Grade.line(%{
        "limits" => [],
        "scores" => %{@low | "blast" => 4},
        "reasons" => %{"blast" => "touches Workline.Merge"},
        "decisions" => ["the howl's wording"]
      })

    assert line =~ "scope 1 · reversibility 1 · blast 4 · detectability 1 · proof 2"
    assert line =~ "(blast: touches Workline.Merge)"
    assert line =~ "leaves you: the howl's wording"
    assert Grade.line(%{"limits" => ["a database migration"]}) =~ "yours to judge — a database migration"
  end

  describe "grade/2 — through the configured grader CLI" do
    setup do
      dir = Path.join(System.tmp_dir!(), "tlon-grader-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      fake = fn reply ->
        cli = Path.join(dir, "grader")
        File.write!(cli, "#!/bin/sh\ncat <<'EOF'\n#{reply}\nEOF\n")
        File.chmod!(cli, 0o755)
        Application.put_env(:server, :grader_cmd, cli)
        on_exit(fn -> Application.delete_env(:server, :grader_cmd) end)
      end

      {:ok, thread} = Workline.open(%{title: "pets", slug: "graded", stage: "review"})
      %{fake: fake, thread: thread}
    end

    test "a grade is recorded as the thread's grade evidence", %{fake: fake, thread: thread} do
      fake.(~s({"scores": #{Jason.encode!(@low)}, "reasons": {}, "decisions": []}))

      assert {:ok, %{"scores" => @low, "limits" => []}} =
               Grade.grade(thread, change: change(), docs: %{spec: "s", plan: "p"})

      assert %{kind: "check_passed", detail: %{"scores" => @low}} = last_grade(thread)
    end

    test "a limit hit is recorded without asking the grader", %{fake: fake, thread: thread} do
      fake.("not json — the grader must not be asked")

      assert {:ok, %{"limits" => [_]}} =
               Grade.grade(thread, change: change(%{lines: 900}), docs: %{spec: "s", plan: "p"})

      assert %{kind: "check_passed"} = last_grade(thread)
    end

    test "an answer that isn't a grade is recorded as a failed grade", %{fake: fake, thread: thread} do
      fake.("looks fine to me")
      assert {:error, why} = Grade.grade(thread, change: change(), docs: %{spec: "s", plan: "p"})
      assert why =~ "not a grade"
      assert %{kind: "check_failed"} = last_grade(thread)
    end
  end

  defp last_grade(thread) do
    import Ecto.Query

    Server.Repo.one(
      from e in Server.Event,
        where: e.correlation == ^"workline:#{thread.slug}:grade",
        order_by: [desc: e.id],
        limit: 1
    )
  end
end
