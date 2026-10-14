defmodule Server.BranchReviewTest do
  # A review on tlon of a branch that is not a workline: what `mise run land` asks for before it
  # opens the PR and merges. The newest verdict on a branch is its verdict.
  use ExUnit.Case, async: false

  alias Server.BranchReview

  @a String.duplicate("a", 40)
  @b String.duplicate("b", 40)

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Server.Channel.open_thread(%{title: "review local-check"})
    %{thread: thread}
  end

  defp review(thread, attrs),
    do:
      BranchReview.record(
        Map.merge(
          %{
            branch: "local-check",
            sha: @a,
            verdict: "approve",
            by: "lonnrot",
            body: "approve: reads right",
            thread_id: thread.id
          },
          attrs
        )
      )

  test "no review: nil" do
    assert BranchReview.latest("local-check") == nil
  end

  test "the newest verdict is the branch's, with its sha, reviewer and body", %{thread: thread} do
    {:ok, _} = review(thread, %{})
    {:ok, _} = review(thread, %{sha: @b, verdict: "request_changes", by: "tzinacan", body: "the lease is wrong"})

    assert %{verdict: "request_changes", sha: @b, by: "tzinacan", body: "the lease is wrong"} =
             BranchReview.latest("local-check")

    assert BranchReview.latest("other") == nil
  end

  describe "approves/4: does the newest verdict let this head land" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp} do
      git = fn cmd ->
        {out, 0} = System.cmd("sh", ["-c", cmd], cd: tmp, stderr_to_stdout: true)
        String.trim(out)
      end

      git.("""
      git init -q && git config user.email t@t && git config user.name t &&
      git commit -q --allow-empty -m one && git branch -M main &&
      git checkout -qb lamp && echo f >f && git add f && git commit -qm lamp && git checkout -q main &&
      echo m >m && git add m && git commit -qm two
      """)

      %{git: git, head: git.("git rev-parse lamp")}
    end

    defp approve(thread, sha, verdict \\ "approve"), do: review(thread, %{branch: "lamp", sha: sha, verdict: verdict})

    test "no review, or changes requested: refused", %{thread: thread, tmp_dir: tmp, head: head} do
      assert {:error, why} = BranchReview.approves(tmp, "lamp", head, "main")
      assert why =~ "no review"
      {:ok, _} = approve(thread, head, "request_changes")
      assert {:error, why} = BranchReview.approves(tmp, "lamp", head, "main")
      assert why =~ "requests changes"
    end

    test "approved at the head: lands", %{thread: thread, tmp_dir: tmp, head: head} do
      {:ok, _} = approve(thread, head)
      assert {:ok, %{by: "lonnrot"}} = BranchReview.approves(tmp, "lamp", head, "main")
    end

    test "approved, then only rebased onto main: the same patches, lands", %{
      thread: thread,
      tmp_dir: tmp,
      head: head,
      git: git
    } do
      {:ok, _} = approve(thread, head)
      rebased = git.("git checkout -q lamp && git rebase -q main && git checkout -q main && git rev-parse lamp")
      refute rebased == head
      assert {:ok, _} = BranchReview.approves(tmp, "lamp", rebased, "main")
    end

    test "approved at an older commit, new commits since: refused", %{
      thread: thread,
      tmp_dir: tmp,
      head: head,
      git: git
    } do
      {:ok, _} = approve(thread, head)

      newer =
        git.(
          "git checkout -q lamp && echo g >g && git add g && git commit -qm more && git checkout -q main && git rev-parse lamp"
        )

      assert {:error, why} = BranchReview.approves(tmp, "lamp", newer, "main")
      assert why =~ "review it again"
    end
  end

  test "refused: main, a short sha, an unknown verdict", %{thread: thread} do
    assert {:error, why} = review(thread, %{branch: "main"})
    assert why =~ "main"
    assert {:error, why} = review(thread, %{sha: "abc123"})
    assert why =~ "40"
    assert {:error, why} = review(thread, %{verdict: "lgtm"})
    assert why =~ "approve"
    assert BranchReview.latest("main") == nil
  end
end
