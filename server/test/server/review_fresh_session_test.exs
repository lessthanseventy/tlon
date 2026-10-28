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

  test "a workline review's verdict ends the reviewer's session too", %{rita: rita} do
    {:ok, thread} = Workline.open(%{title: "fix the lamp", slug: "lamp-fix", stage: "review"})
    {:ok, thread} = Staff.assign(thread, rita)
    {:ok, session} = Staff.start_session(%{agent_id: rita.id, thread_id: thread.id, pane_ref: "t#{thread.id}"})

    assert {:error, {:bounced, _}} = Workline.review_verdict(thread, "request_changes", rita.name)
    assert %DateTime{} = Repo.get!(Session, session.id).ended_at
  end

  # A workline at review on a bench with a builder, a reviewer and a qa seat, lonnrot leading.
  defp benched_review(slug) do
    roster = [
      %{"archetype" => "builder", "name" => "hronir"},
      %{"archetype" => "reviewer", "name" => "lonnrot"},
      %{"archetype" => "qa", "name" => "nolan"}
    ]

    {:ok, ws} = Server.Workspaces.register(%{name: "Fates #{slug}", roster: roster})
    {:ok, thread} = Workline.open(%{title: "fix the #{slug}", slug: slug, stage: "review", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(thread.id, "lonnrot")
    Repo.get!(Server.Thread, thread.id)
  end

  defp follow_up_post(thread) do
    thread
    |> Channel.thread_messages()
    |> Enum.map(& &1.body)
    |> Enum.find(&(&1 =~ "follow-ups from lonnrot's review"))
  end

  describe "a review's follow-ups are addressed to the lead the verdict hands to" do
    setup do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      :ok
    end

    test "request_changes: the builder, never the reviewer whose session just ended" do
      thread = benched_review("wick")

      assert {:error, {:bounced, _}} =
               Workline.review_verdict(thread, "request_changes", "lonnrot",
                 branch_head: nil,
                 follow_ups: ["a typo in the help"]
               )

      assert Channel.thread_lead(thread.id) == "hronir"
      post = follow_up_post(thread)
      assert post =~ "@hronir" and post =~ "1. a typo in the help"
      refute post =~ "@lonnrot"
    end

    test "approve with QA owed: the qa seat" do
      thread = benched_review("knob")

      assert {:ok, _} =
               Workline.review_verdict(thread, "approve", "lonnrot",
                 branch_head: nil,
                 paths: ["office/kit/room.ts"],
                 follow_ups: ["the tooltip wraps"]
               )

      assert Channel.thread_lead(thread.id) == "nolan"
      assert follow_up_post(thread) =~ "@nolan"
    end

    test "approve handed to the operator's gate: the operator" do
      thread = benched_review("lamp")

      assert {:ok, _} =
               Workline.review_verdict(thread, "approve", "lonnrot",
                 artifacts: Server.TestArtifacts.Present,
                 branch_head: nil,
                 paths: ["server/lib/server/workline.ex"],
                 follow_ups: ["clean! could clear stray rows"]
               )

      assert Channel.thread_lead(thread.id) == "lonnrot"
      post = follow_up_post(thread)
      assert post =~ "@#{Server.OperatorConfig.operator()}"
      refute post =~ "@lonnrot"
    end
  end

  test "the operator's read of a review-stage thread keeps the conversation", %{rita: rita} do
    {:ok, thread} = Workline.open(%{title: "fix the lamp", slug: "lamp-fix", stage: "review"})
    {:ok, thread} = Staff.assign(thread, rita)
    {:ok, _} = Channel.post(%{thread_id: thread.id, author: "builder", body: "builder-chatter-7f3a"})

    assert inspect(Board.brief(thread), limit: :infinity) =~ "builder-chatter-7f3a"
  end
end
