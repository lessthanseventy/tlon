defmodule Server.WorklinePublishTest do
  # A workline approved on this machine also reaches GitHub, whose main takes only PRs: the branch is
  # pushed, a PR opened, and merged by GitHub once its checks pass.
  use ExUnit.Case, async: true

  alias Server.Workline.Publish

  defp runner(replies) do
    test = self()

    fn cmd, args, _opts ->
      send(test, {:ran, [cmd | args]})
      reply(replies, [cmd | args])
    end
  end

  defp reply(replies, argv), do: Enum.find_value(replies, {"", 0}, fn {match, r} -> match.(argv) && r end)

  test "pushes the branch, opens a PR, asks GitHub to merge it once green" do
    run = runner([{&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}}])
    assert {:ok, "https://github.com/o/r/pull/9"} = Publish.publish("/repo", "tiles", "Floor step 1", run)

    assert_received {:ran, ["git", "-C", "/repo", "remote", "get-url", "origin"]}
    assert_received {:ran, ["git", "-C", "/repo", "push", "--force-with-lease", "origin", "work/tiles"]}

    assert_received {:ran,
                     ["gh", "pr", "create", "--head", "work/tiles", "--base", "main", "--title", "Floor step 1" | _]}

    assert_received {:ran,
                     ["gh", "pr", "merge", "https://github.com/o/r/pull/9", "--rebase", "--auto", "--delete-branch"]}
  end

  test "a landing its gate passed posts tlon/check on the sha it gated, so GitHub's required check is there" do
    run = runner([{&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}}])
    assert {:ok, _} = Publish.publish("/repo", "tiles", "Floor step 1", run, gated: "abc123")

    assert_received {:ran,
                     [
                       "gh",
                       "api",
                       "repos/{owner}/{repo}/statuses/abc123",
                       "-f",
                       "state=success",
                       "-f",
                       "context=tlon/check" | _
                     ]}

    assert_received {:ran,
                     [
                       "gh",
                       "pr",
                       "merge",
                       "https://github.com/o/r/pull/9",
                       "--rebase",
                       "--match-head-commit",
                       "abc123"
                     ]}

    assert_received {:ran, ["gh", "api", "-X", "DELETE", "repos/{owner}/{repo}/git/refs/heads/work/tiles"]}
    refute_received {:ran, ["gh", "pr", "merge", _, "--rebase", "--auto" | _]}
  end

  test "an immediate merge never touches local branches; the remote head's delete failing is no failed landing" do
    run =
      runner([
        {&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}},
        {&match?(["gh", "api", "-X", "DELETE" | _], &1), {"Reference does not exist", 1}}
      ])

    assert {:ok, "https://github.com/o/r/pull/9"} = Publish.publish("/repo", "tiles", "t", run, gated: "abc123")
    assert_received {:ran, ["gh", "pr", "merge" | merge]}
    refute "--delete-branch" in merge
  end

  test "GitHub not having evaluated the fresh tlon/check yet: auto-merge armed at that head, not a refusal" do
    run =
      runner([
        {&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}},
        {&match?(["gh", "pr", "merge", _, "--rebase", "--match-head-commit" | _], &1),
         {"X Pull request o/r#9 is not mergeable: Required status check \"tlon/check\" is expected.\n", 1}}
      ])

    assert {:ok, "https://github.com/o/r/pull/9"} = Publish.publish("/repo", "tiles", "t", run, gated: "abc123")

    assert_received {:ran,
                     [
                       "gh",
                       "pr",
                       "merge",
                       "https://github.com/o/r/pull/9",
                       "--rebase",
                       "--auto",
                       "--match-head-commit",
                       "abc123"
                     ]}

    refute_received {:ran, ["gh", "api", "-X", "DELETE" | _]}
  end

  test "a publish no gate passed posts no status, and merges nothing itself: auto-merge waits for one" do
    run = runner([{&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}}])
    assert {:ok, _} = Publish.publish("/repo", "tiles", "Floor step 1", run)
    refute_received {:ran, ["gh", "api" | _]}
    refute_received {:ran, ["gh", "pr", "merge", _, "--rebase", "--match-head-commit" | _]}
  end

  test "GitHub refusing auto-merge is said, with the PR it opened" do
    run =
      runner([
        {&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}},
        {&match?(["gh", "pr", "merge" | _], &1), {"auto-merge is not allowed for this repository\n", 1}}
      ])

    assert {:auto_refused, "https://github.com/o/r/pull/9", "auto-merge is not allowed for this repository"} =
             Publish.publish("/repo", "tiles", "Floor step 1", run)
  end

  describe "the PR's body — what a reader of the PR needs, from the branch itself" do
    defp git_show(name, text), do: {&match?(["git", _, _, "show", "work/tiles:work/tiles/" <> ^name], &1), {text, 0}}
    defp git_log(text), do: {&match?(["git", _, _, "log" | _], &1), {text, 0}}
    defp git_stat(text), do: {&match?(["git", _, _, "diff", "--shortstat" | _], &1), {text, 0}}

    defp body_of(replies) do
      pr = {&match?(["gh", "pr", "create" | _], &1), {"https://github.com/o/r/pull/9\n", 0}}
      {:ok, _} = Publish.publish("/repo", "tiles", "Floor step 1", runner([pr | replies]))
      assert_received {:ran, ["gh", "pr", "create" | args]}
      args |> Enum.drop_while(&(&1 != "--body")) |> Enum.at(1)
    end

    test "the lead's pr.md, the commits, the size and the review's verdict" do
      body =
        body_of([
          git_show("pr.md", "Floors get tiles (ticket #54): the office drew bare boards.\nChecked: bun test.\n"),
          git_show(
            "review.md",
            "# Review — floors\n\n*Reviewed by tzinacan; the verdict is below*\n\n**Verdict: approve.**\n\nfindings…\n"
          ),
          git_log("- office: tiles (pure)\n- office: draw the tiles\n"),
          git_stat(" 3 files changed, 120 insertions(+), 4 deletions(-)\n")
        ])

      assert body =~ "Floors get tiles (ticket #54): the office drew bare boards.\nChecked: bun test."
      assert body =~ "- office: tiles (pure)\n- office: draw the tiles"
      assert body =~ "3 files changed, 120 insertions(+), 4 deletions(-)"
      assert body =~ "**Verdict: approve.**"
      refute body =~ "findings"
      assert body =~ "work/tiles/"
    end

    test "with no pr.md it says what the plan is for, never just the slug" do
      body = body_of([git_show("plan.md", "# Plan — floor tiles (ticket #54)\n\nSpec: …\n")])
      assert body =~ "Plan — floor tiles (ticket #54)"
      refute body =~ "Spec: …"
    end

    test "a workline that started at build has no plan: the spec's title, else the intent's" do
      assert body_of([git_show("intent.md", "# Floors want tiles\n")]) =~ "Floors want tiles"
    end
  end

  test "a repo with no remote has nothing to publish to" do
    run = runner([{&match?(["git", _, _, "remote" | _], &1), {"error: No such remote", 2}}])
    assert Publish.publish("/repo", "tiles", "t", run) == :none
    refute_received {:ran, ["git", _, _, "push" | _]}
  end

  test "a push GitHub refuses is an error the operator can act on" do
    run = runner([{&match?(["git", _, _, "push" | _], &1), {"rejected", 1}}])
    assert {:error, why} = Publish.publish("/repo", "tiles", "t", run)
    assert why =~ "push"
  end

  describe "follow_main/2 — the main checkout mirrors origin/main, fast-forward only" do
    defp on(branch), do: {&match?(["git", "-C", _, "symbolic-ref", "--short", "HEAD"], &1), {branch <> "\n", 0}}
    defp ancestor(code), do: {&match?(["git", "-C", _, "merge-base", "--is-ancestor" | _], &1), {"", code}}

    test "behind origin/main: fetched and fast-forwarded" do
      run = runner([on("main"), ancestor(0)])
      assert :forwarded = Publish.follow_main("/repo", run)
      assert_received {:ran, ["git", "-C", "/repo", "fetch", "-q", "origin", "main"]}
      assert_received {:ran, ["git", "-C", "/repo", "merge", "--ff-only", "-q", "origin/main"]}
    end

    test "a checkout on another branch is left alone" do
      run = runner([on("work/x")])
      assert :skipped = Publish.follow_main("/repo", run)
      refute_received {:ran, ["git", "-C", _, "fetch" | _]}
    end

    test "main with commits of its own is never merged or rewritten — it says how far it has drifted" do
      run = runner([on("main"), ancestor(1), {&match?(["git", "-C", _, "rev-list", "--count" | _], &1), {"4\n", 0}}])
      assert {:diverged, 4} = Publish.follow_main("/repo", run)
      refute_received {:ran, ["git", "-C", _, "merge", "--ff-only" | _]}
    end
  end

  describe "failing/2 — a landing whose checks went red, so auto-merge never fires" do
    @red Jason.encode!([
           %{
             "number" => 80,
             "headRefName" => "work/red",
             "statusCheckRollup" => [
               %{"conclusion" => "SUCCESS", "name" => "lint"},
               %{"conclusion" => "FAILURE", "name" => "check"}
             ]
           },
           %{"number" => 81, "headRefName" => "work/green", "statusCheckRollup" => [%{"conclusion" => "SUCCESS"}]},
           %{"number" => 82, "headRefName" => "work/pending", "statusCheckRollup" => [%{"conclusion" => ""}]},
           %{"number" => 83, "headRefName" => "work/status", "statusCheckRollup" => [%{"state" => "ERROR"}]},
           %{"number" => 84, "headRefName" => "fix/mine", "statusCheckRollup" => [%{"conclusion" => "FAILURE"}]}
         ])

    test "its own PRs with a failed check, by slug — never pending, green or a human's branch" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {@red, 0}}])
      assert [%{number: 80, slug: "red"}, %{number: 83, slug: "status"}] = Publish.failing("/repo", run)
    end

    test "a repo gh can't read is an error, never an empty list" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {"no git remotes found", 1}}])
      assert {:error, "gh pr list exited 1: " <> _} = Publish.failing("/repo", run)
    end
  end

  describe "conflicting/2 — a landing GitHub can never merge: main moved under it and they conflict" do
    @prs Jason.encode!([
           %{"number" => 73, "headRefName" => "work/tangled", "mergeStateStatus" => "DIRTY"},
           %{"number" => 74, "headRefName" => "work/behind", "mergeStateStatus" => "BEHIND"},
           %{"number" => 75, "headRefName" => "fix/mine", "mergeStateStatus" => "DIRTY"}
         ])

    test "its own landings that conflict, by slug — never a human's branch" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {@prs, 0}}])
      assert [%{number: 73, slug: "tangled"}] = Publish.conflicting("/repo", run)
    end

    test "a repo gh can't read is an error, never an empty list" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {"no git remotes found", 1}}])
      assert {:error, "gh pr list exited 1: " <> _} = Publish.conflicting("/repo", run)
    end

    test "close/3 closes the PR, saying why, and keeps its branch for the next landing" do
      run = runner([])
      assert :ok = Publish.close("/repo", 73, "main moved under it", run)
      assert_received {:ran, ["gh", "pr", "close", "73", "--comment", "main moved under it"]}
    end
  end

  describe "push_branch/3 — the one way a coworker's branch reaches GitHub" do
    test "force-pushes a work/* branch with a lease" do
      run = runner([])
      assert :ok = Publish.push_branch("/repo", "work/tiles", run)
      assert_received {:ran, ["git", "-C", "/repo", "push", "--force-with-lease", "origin", "work/tiles"]}
    end

    test "never main, nor any branch that isn't a thread's" do
      run = runner([])
      for b <- ["main", "fix/mine", "work/../main"], do: assert({:error, _} = Publish.push_branch("/repo", b, run))
      refute_received {:ran, _}
    end

    test "a refused push says why" do
      run = runner([{&match?(["git", "-C", "/repo", "push" | _], &1), {"stale info", 1}}])
      assert {:error, why} = Publish.push_branch("/repo", "work/tiles", run)
      assert why =~ "stale info"
    end
  end
end
