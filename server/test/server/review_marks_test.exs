defmodule Server.ReviewMarksTest do
  use ExUnit.Case, async: false

  alias Server.ReviewMarks

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "marks-#{System.pid()}-#{System.unique_integer([:positive])}")
    repo = Path.join(dir, "repo")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(dir) end)

    git(repo, ~w(init -q -b main))
    commit(repo, "a")
    git(repo, ~w(update-ref refs/remotes/origin/main HEAD))
    git(repo, ~w(switch -q -c feat))
    commit(repo, "b")
    %{repo: repo, dir: dir}
  end

  defp git(repo, args) do
    env = [{"GIT_AUTHOR_NAME", "ada"}, {"GIT_AUTHOR_EMAIL", "a@x"}, {"GIT_COMMITTER_NAME", "ada"}]

    {out, 0} =
      System.cmd("git", ["-C", repo | args], env: [{"GIT_COMMITTER_EMAIL", "a@x"} | env], stderr_to_stdout: true)

    String.trim(out)
  end

  defp commit(repo, text) do
    File.write!(Path.join(repo, "f"), text)
    git(repo, ~w(add f))
    git(repo, ["commit", "-q", "-m", text])
  end

  defp review(repo, verdict) do
    Server.BranchReview.record(%{
      branch: "feat",
      sha: git(repo, ~w(rev-parse HEAD)),
      verdict: verdict,
      by: "anthropic/claude-sonnet-5-5",
      body: "read",
      thread_id: nil
    })
  end

  defp swept(repo, panes, queued \\ false) do
    me = self()

    tmux = fn
      ["list-panes" | _] -> {Enum.map_join(panes, "\n", fn {id, dir, had} -> "#{id}\t#{dir}\t#{had}" end), 0}
      set -> send(me, {:tmux, set})
    end

    ReviewMarks.sweep(tmux: tmux, repo: repo, queued: fn "feat" -> queued end)
  end

  test "a pane on a branch whose newest review is of its head is marked with the verdict", %{repo: repo} do
    {:ok, _} = review(repo, "approve")

    swept(repo, [{"%1", repo, ""}])
    assert_received {:tmux, ["set-option", "-p", "-t", "%1", "@arena_review", "reviewed"]}

    {:ok, _} = review(repo, "request_changes")
    swept(repo, [{"%1", repo, "reviewed"}])
    assert_received {:tmux, ["set-option", "-p", "-t", "%1", "@arena_review", "changes"]}
  end

  test "a commit made after the review clears the mark, and a mark that is right is left alone", %{repo: repo} do
    {:ok, _} = review(repo, "approve")
    swept(repo, [{"%1", repo, "reviewed"}])
    refute_received {:tmux, _}

    commit(repo, "c")
    swept(repo, [{"%1", repo, "reviewed"}])
    assert_received {:tmux, ["set-option", "-p", "-u", "-t", "%1", "@arena_review"]}
  end

  test "queued while its landing is in the queue, landed once the reviewed commit is on origin's main", %{repo: repo} do
    {:ok, _} = review(repo, "approve")

    swept(repo, [{"%1", repo, "reviewed"}], true)
    assert_received {:tmux, ["set-option", "-p", "-t", "%1", "@arena_review", "queued"]}

    git(repo, ~w(update-ref refs/remotes/origin/main HEAD))
    swept(repo, [{"%1", repo, "queued"}])
    assert_received {:tmux, ["set-option", "-p", "-t", "%1", "@arena_review", "landed"]}
  end

  test "landed when main holds the reviewed commit under another name, as a rebase-merge leaves it", %{repo: repo} do
    {:ok, _} = review(repo, "approve")
    reviewed = git(repo, ~w(rev-parse HEAD))
    git(repo, ~w(switch -q --detach refs/remotes/origin/main))
    git(repo, ["cherry-pick", "-x", reviewed])
    refute git(repo, ~w(rev-parse HEAD)) == reviewed
    git(repo, ~w(update-ref refs/remotes/origin/main HEAD))
    git(repo, ~w(switch -q feat))

    swept(repo, [{"%1", repo, "reviewed"}])
    assert_received {:tmux, ["set-option", "-p", "-t", "%1", "@arena_review", "landed"]}
  end

  test "main, an unreviewed branch, and a pane somewhere else carry no mark", %{repo: repo, dir: dir} do
    swept(repo, [{"%1", repo, ""}, {"%2", dir, ""}, {"%3", "/nonexistent", ""}])
    refute_received {:tmux, _}

    {:ok, _} = review(repo, "approve")
    git(repo, ~w(switch -q main))
    swept(repo, [{"%1", repo, ""}])
    refute_received {:tmux, _}
  end

  test "with tmux down nothing is done", %{repo: repo} do
    assert ReviewMarks.sweep(tmux: fn _ -> {"no server running", 1} end, repo: repo, queued: fn _ -> false end) == :ok
  end
end
