defmodule Server.ReviewFreshSessionTest do
  # #356: every review runs in a fresh, throwaway session. The verdict ends the reviewer's session
  # and closes its leaf; a reviewer's brief carries the branch, diff, spec/plan and checklist, never
  # the builder's conversation; a round-2 reviewer still gets its `last_reviewed` pointer.
  use ExUnit.Case, async: false

  alias Server.Board
  alias Server.Channel
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Workline

  setup do
    Application.put_env(:server, :arbiter, Server.Arbiter.Test)
    Application.put_env(:server, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)

    Server.TestDB.clean!()
    {:ok, rita} = Staff.register_agent(%{name: "Rita", mandate: "reviewer", engine: "fresh"})
    %{rita: rita}
  end

  defp head_sha do
    {head, 0} = System.cmd("git", ["-C", Server.Profiles.tlon_root(), "rev-parse", "HEAD"])
    String.trim(head)
  end

  # A review thread for `branch`, led by `reviewer`, with the session its spawn gave it.
  defp review_thread(reviewer, branch) do
    {:ok, thread} = Channel.open_thread(%{title: "review #{branch}"})
    {:ok, _} = Staff.assign(thread, reviewer)
    {:ok, session} = Staff.start_session(%{agent_id: reviewer.id, thread_id: thread.id, pane_ref: "t#{thread.id}"})
    {thread, session}
  end

  defp verdict!(thread, branch, by) do
    {:ok, _} =
      Server.BranchReview.record(%{
        branch: branch,
        sha: head_sha(),
        verdict: "approve",
        by: by,
        body: "approve: ok",
        thread_id: thread.id,
        repo: Server.Profiles.tlon_root()
      })
  end

  test "two consecutive reviews on one reviewer handle get two distinct sessions", %{rita: rita} do
    {t1, s1} = review_thread(rita, "lamp")
    verdict!(t1, "lamp", rita.name)

    assert %DateTime{} = Repo.get!(Session, s1.id).ended_at
    assert Server.Staffing.leaf_window(t1, "test") == nil

    {t2, s2} = review_thread(rita, "sconce")
    verdict!(t2, "sconce", rita.name)

    ids = Session |> Repo.all() |> Enum.filter(&(&1.agent_id == rita.id)) |> Enum.map(& &1.id)
    assert Enum.sort(ids) == Enum.sort([s1.id, s2.id])
    assert s1.id != s2.id
    assert %DateTime{} = Repo.get!(Session, s2.id).ended_at
  end

  test "the second review's opening brief carries nothing from the first thread", %{rita: rita} do
    {t1, _} = review_thread(rita, "lamp")
    {:ok, _} = Channel.post(%{thread_id: t1.id, author: "builder", body: "builder-chatter-7f3a"})
    verdict!(t1, "lamp", rita.name)

    {t2, _} = review_thread(rita, "sconce")
    brief = t2 |> Board.brief(viewer: rita.name) |> Server.MCP.Brief.scope()

    refute inspect(brief, limit: :infinity) =~ "builder-chatter-7f3a"
  end

  test "a round-2 workline review keeps its last_reviewed pointer without thread posts", %{rita: rita} do
    {:ok, thread} = Workline.open(%{title: "fix the lamp", slug: "lamp-fix", stage: "review"})
    {:ok, thread} = Staff.assign(thread, rita)
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "builder", body: "builder-chatter-7f3a"})
    sha = head_sha()

    {:ok, _} =
      Server.Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "review verdict by Rita",
        exit: 1,
        tail: "request_changes",
        correlation: "workline:#{thread.slug}:review",
        sha: sha
      })

    stage_brief = Workline.Brief.stage_message(thread, last_reviewed: sha)
    assert stage_brief =~ "You reviewed this before, at #{String.slice(sha, 0, 7)}"
    assert stage_brief =~ "review.md"

    brief = thread |> Board.brief(viewer: rita.name) |> Server.MCP.Brief.scope()
    assert brief["recent"] == []
    assert brief["opening"] == nil
    refute inspect(brief, limit: :infinity) =~ "builder-chatter-7f3a"
  end

  test "the operator's read of a review-stage thread keeps the conversation", %{rita: rita} do
    {:ok, thread} = Workline.open(%{title: "fix the lamp", slug: "lamp-fix", stage: "review"})
    {:ok, thread} = Staff.assign(thread, rita)
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "builder", body: "builder-chatter-7f3a"})

    assert inspect(Board.brief(thread), limit: :infinity) =~ "builder-chatter-7f3a"
  end
end
