defmodule Server.Workline.GradeTest do
  use ExUnit.Case, async: false

  alias Server.Workline
  alias Server.Workline.Grade

  @low %{"scope" => 1, "reversibility" => 1, "blast" => 2, "detectability" => 1, "proof" => 2}
  @file_text "export function say(line) {\n  return pick(line, recent)\n}\n"
  @material "+  return pick(line, recent)\n" <> @file_text

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp change(attrs \\ %{}) do
    Map.merge(
      %{
        paths: ["office/kit/pets.ts"],
        deleted: [],
        lines: 40,
        diff: "+  return pick(line, recent)\n",
        files: [{"office/kit/pets.ts", @file_text}]
      },
      attrs
    )
  end

  # the grader's answer: every axis's reason quoting `quote`
  defp answer(scores, quote, extra \\ %{}) do
    Jason.encode!(
      Map.merge(
        %{
          "scores" => scores,
          "reasons" => Map.new(Grade.axes(), &{&1, %{"why" => "#{&1} looks fine", "quote" => quote}}),
          "decisions" => [],
          "fixes" => []
        },
        extra
      )
    )
  end

  defp grounded(scores) do
    %{
      "limits" => [],
      "decisions" => [],
      "fixes" => [],
      "scores" => scores,
      "reasons" =>
        Map.new(Grade.axes(), &{&1, %{"why" => "fine", "quote" => "q", "kind" => "fact", "grounded" => true}})
    }
  end

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

  describe "the prompt" do
    test "carries every changed file in full, not only the diff" do
      prompt = Grade.prompt("the ticket", nil, change())
      assert prompt =~ "office/kit/pets.ts"
      assert prompt =~ @file_text
      assert prompt =~ "+  return pick(line, recent)"
    end

    test "a file past the budget is named as left out, never silently dropped" do
      big = String.duplicate("x", 300_000)
      prompt = Grade.prompt("t", nil, change(%{files: [{"a.ex", "small"}, {"b.ex", big}]}))
      assert prompt =~ "small"
      refute prompt =~ big
      assert prompt =~ "b.ex — not included"
    end
  end

  describe "parse — each claim's quote checked against the change" do
    test "a quote found in the diff or the files is grounded; one that isn't, isn't" do
      text =
        Jason.encode!(%{
          "scores" => @low,
          "reasons" =>
            Map.merge(
              Map.new(Grade.axes(), &{&1, %{"why" => "ok", "quote" => "return pick(line, recent)"}}),
              %{"blast" => %{"why" => "the script runs under set -e", "quote" => "set -euo pipefail"}}
            ),
          "fixes" => [
            %{"fix" => "pin it", "quote" => "export   function say(line)"},
            %{"fix" => "imagined", "quote" => "nowhere in the change"}
          ]
        })

      assert {:ok, grade} = Grade.parse("```json\n" <> text <> "\n```", @material)
      assert grade["reasons"]["scope"]["grounded"]
      refute grade["reasons"]["blast"]["grounded"]
      # whitespace differences don't unground a real line
      assert [%{"grounded" => true}, %{"grounded" => false}] = grade["fixes"]
    end

    test "an opinion is kept as one: labelled, never counted as checked, whatever its quote" do
      text =
        answer(@low, "return pick(line, recent)", %{
          "fixes" => [
            %{"fix" => "a `with` reads better than the nested case", "quote" => "nowhere", "kind" => "opinion"}
          ]
        })

      assert {:ok, grade} = Grade.parse(text, @material)
      assert [%{"kind" => "opinion", "grounded" => false}] = grade["fixes"]
      assert grade["reasons"]["scope"]["kind"] == "fact"
    end

    test "an empty quote is never grounded" do
      assert {:ok, grade} = Grade.parse(answer(@low, ""), @material)
      refute grade["reasons"]["scope"]["grounded"]
    end

    test "an axis missing or out of range is not a grade" do
      assert {:error, why} = Grade.parse(~s({"scores": {"scope": 1}}), @material)
      assert why =~ "not a grade"
      assert {:error, _} = Grade.parse(answer(%{@low | "blast" => 9}, "x"), @material)
      assert {:error, _} = Grade.parse("I think it's fine", @material)
    end
  end

  describe "allows?" do
    test "every axis at or under the threshold, each reason grounded, no limit, nothing left to decide" do
      grade = grounded(@low)
      assert Grade.allows?(grade, 2)
      refute Grade.allows?(grade, 1)
      refute Grade.allows?(%{grade | "decisions" => ["what the pet says"]}, 5)
      refute Grade.allows?(%{"limits" => ["a database migration"]}, 5)
      refute Grade.allows?(nil, 5)
    end

    test "a low score resting on an opinion never lands unattended" do
      grade =
        put_in(grounded(@low), ["reasons", "blast"], %{
          "why" => "idiomatic",
          "quote" => "q",
          "kind" => "opinion",
          "grounded" => true
        })

      refute Grade.allows?(grade, 5)
    end

    test "a low score whose evidence doesn't check out never lands unattended" do
      grade = put_in(grounded(@low), ["reasons", "proof", "grounded"], false)
      refute Grade.allows?(grade, 5)
    end
  end

  test "the card line: every axis, the worst one's reason, what it leaves you, an unverified mark" do
    grade =
      put_in(%{grounded(%{@low | "blast" => 4}) | "decisions" => ["the howl's wording"]}, ["reasons", "blast"], %{
        "why" => "touches Workline.Merge",
        "quote" => "q",
        "grounded" => false
      })

    line = Grade.line(grade)
    assert line =~ "scope 1 · reversibility 1 · blast 4 · detectability 1 · proof 2"
    assert line =~ "(blast: touches Workline.Merge ⚠ unverified)"
    assert line =~ "leaves you: the howl's wording"
    assert Grade.line(%{"limits" => ["a database migration"]}) =~ "yours to judge — a database migration"
  end

  test "the report: each claim with its evidence, or marked unverified" do
    grade =
      %{
        grounded(%{@low | "proof" => 4})
        | "fixes" => [
            %{"fix" => "add a test", "quote" => "say(line)", "kind" => "fact", "grounded" => true},
            %{"fix" => "prefer a with", "quote" => "say(line)", "kind" => "opinion", "grounded" => true}
          ]
      }
      |> put_in(["reasons", "proof"], %{"why" => "no test", "quote" => "set -e", "grounded" => false})
      |> put_in(["reasons", "scope"], %{
        "why" => "on ticket",
        "quote" => "return pick(line, recent)",
        "grounded" => true
      })

    report = Grade.report(grade)
    assert report =~ "scope 1 — on ticket\n    ↳ `return pick(line, recent)`"
    assert report =~ "proof 4 — no test\n    ⚠ unverified: its quote is not in the change"
    assert report =~ "- add a test\n    ↳ `say(line)`"
    assert report =~ "- prefer a with\n    (opinion) ↳ `say(line)`"
    assert report =~ "- prefer a with\n    (opinion) ↳ `say(line)`"
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

    test "a grade is recorded, its quotes checked against this change", %{fake: fake, thread: thread} do
      fake.(answer(@low, "return pick(line, recent)"))

      assert {:ok, %{"scores" => @low, "limits" => []} = grade} =
               Grade.grade(thread, change: change(), docs: %{spec: "s", plan: "p"})

      assert Enum.all?(Grade.axes(), &grade["reasons"][&1]["grounded"])
      assert %{kind: "check_passed", detail: %{"scores" => @low}} = last_grade(thread)
    end

    test "the full report goes on the thread", %{fake: fake, thread: thread} do
      fake.(
        answer(%{@low | "proof" => 5}, "return pick(line, recent)", %{
          "decisions" => ["whether pets may sit on the operator's desk"],
          "fixes" => [
            %{"fix" => "add a test that runs say() on a recent line", "quote" => "export function say(line) {"}
          ]
        })
      )

      assert {:ok, _} = Grade.grade(thread, change: change(), docs: %{spec: "s", plan: "p"})
      assert [report] = for(m <- Server.Channel.thread_messages(thread), m.author == "grader", do: m.body)
      assert report =~ "proof 5 — proof looks fine"
      assert report =~ "whether pets may sit on the operator's desk"
      assert report =~ "add a test that runs say() on a recent line\n    ↳ `export function say(line) {`"
    end

    test "a limit hit is recorded and said on the thread, without asking the grader", %{fake: fake, thread: thread} do
      fake.("not json — the grader must not be asked")

      assert {:ok, %{"limits" => [_]}} =
               Grade.grade(thread, change: change(%{lines: 900}), docs: %{spec: "s", plan: "p"})

      assert %{kind: "check_passed"} = last_grade(thread)

      assert Enum.any?(
               Server.Channel.thread_messages(thread),
               &(&1.author == "grader" and &1.body =~ "900 changed lines")
             )
    end

    test "assess/2 grades a change outside any workline and records nothing", %{fake: fake} do
      fake.(answer(@low, "return pick(line, recent)"))
      assert {:ok, %{"scores" => @low, "limits" => []}} = Grade.assess(change(), %{spec: "s", plan: nil})

      assert {:ok, %{"limits" => ["a database migration"]}} =
               Grade.assess(change(%{paths: ["server/priv/repo/migrations/1_x.exs"]}), %{spec: "s", plan: nil})

      assert Server.Repo.aggregate(Server.Event, :count) == 0
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
