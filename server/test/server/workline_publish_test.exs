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

  describe "refresh_behind/2 — a landing GitHub won't merge because main moved under it" do
    @prs Jason.encode!([
           %{"number" => 69, "headRefName" => "work/floor", "mergeStateStatus" => "BEHIND", "autoMergeRequest" => %{}},
           %{"number" => 70, "headRefName" => "work/clean", "mergeStateStatus" => "CLEAN", "autoMergeRequest" => %{}},
           %{"number" => 71, "headRefName" => "fix/mine", "mergeStateStatus" => "BEHIND", "autoMergeRequest" => %{}},
           %{"number" => 72, "headRefName" => "work/held", "mergeStateStatus" => "BEHIND", "autoMergeRequest" => nil}
         ])

    test "rebases only its own landings that wait on auto-merge and are behind — never a human's branch" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {@prs, 0}}])
      assert [69] = Publish.refresh_behind("/repo", run)
      assert_received {:ran, ["gh", "pr", "update-branch", "69", "--rebase"]}
      refute_received {:ran, ["gh", "pr", "update-branch", _ | _]}
    end

    test "a repo gh can't read (no remote, no auth) is nothing to do" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {"no git remotes found", 1}}])
      assert [] = Publish.refresh_behind("/repo", run)
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

    test "a repo gh can't read is nothing to do" do
      run = runner([{&match?(["gh", "pr", "list" | _], &1), {"no git remotes found", 1}}])
      assert [] = Publish.conflicting("/repo", run)
    end

    test "close/3 closes the PR, saying why, and keeps its branch for the next landing" do
      run = runner([])
      assert :ok = Publish.close("/repo", 73, "main moved under it", run)
      assert_received {:ran, ["gh", "pr", "close", "73", "--comment", "main moved under it"]}
    end
  end
end
