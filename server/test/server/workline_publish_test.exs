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
end
