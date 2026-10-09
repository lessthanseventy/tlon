defmodule Server.WorklineReviewHeadTest do
  # A review approves the code it read: its verdict records the branch's commit, and code committed
  # after it sends the workline back to build like any other change, never landing on the old
  # approval (the workline's own docs, work/<slug>/, may move: review.md is committed after the
  # verdict). Coming back, the reviewer is pointed at what changed since its last look.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  defmodule Merges do
    @moduledoc false
    def merge(_repo, _slug, _opts \\ []), do: {:ok, %{from: "a", to: "b"}}
  end

  defmodule GatedMerges do
    @moduledoc false
    def merge(repo, slug, opts) do
      with {:ok, :green} <- Keyword.fetch!(opts, :gate).(repo, "work/#{slug}"), do: {:ok, %{from: "a", to: "b"}}
    end
  end

  setup do
    Server.TestDB.clean!()
    root = Path.join(System.tmp_dir!(), "review-head-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    git(root, ["init", "-q", "-b", "main"])
    git(root, ["config", "user.email", "t@t"])
    git(root, ["config", "user.name", "t"])
    commit(root, "seed", "s")
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, root)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  defp git(root, args), do: {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)

  defp commit(root, path, text) do
    File.mkdir_p!(Path.dirname(Path.join(root, path)))
    File.write!(Path.join(root, path), text)
    git(root, ["add", "-A"])
    git(root, ["commit", "-qm", path])
  end

  # a workline at review whose branch carries one change
  defp at_review(root, slug) do
    git(root, ["checkout", "-q", "-b", "work/#{slug}"])
    commit(root, "lib/#{slug}.ex", "v1")
    git(root, ["checkout", "-q", "main"])

    roster = [%{"archetype" => "builder", "name" => "emma"}, %{"archetype" => "reviewer", "name" => "lonnrot"}]
    {:ok, ws} = Server.Workspaces.register(%{name: "Head #{slug}", roster: roster})
    {:ok, built} = Workline.open(%{title: "t #{slug}", slug: slug, stage: "build", workspace_id: ws.id})
    {:ok, _} = Channel.assign_lead(built.id, "emma")
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, built.id), artifacts: AllPresent)
    {:ok, reviewing} = Workline.advance(verifying, artifacts: AllPresent)
    reviewing
  end

  defp on_branch(root, slug, path, text) do
    git(root, ["checkout", "-q", "work/#{slug}"])
    commit(root, path, text)
    git(root, ["checkout", "-q", "main"])
  end

  defp parked(thread) do
    {:awaiting, parked} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
    parked
  end

  test "a review verdict records the commit it read", %{root: root} do
    thread = at_review(root, "records")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)

    sha =
      Repo.one(
        from e in Server.Event,
          where: e.thread_id == ^thread.id and e.correlation == "workline:records:review",
          select: e.detail
      )["sha"]

    assert {head, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/records"])
    assert sha == String.trim(head)
  end

  test "the reviewed code lands, docs committed after it or not; code committed after it goes back to build",
       %{root: root} do
    same = at_review(root, "same")
    {:ok, _} = Workline.review_verdict(same, "approve", "lonnrot", artifacts: AllPresent)
    on_branch(root, "same", "work/same/review.md", "approve")
    assert {:ok, %{stage: "merged"}} = Workline.approve(parked(same), artifacts: AllPresent, merge: Merges)

    moved = at_review(root, "moved")
    {:ok, _} = Workline.review_verdict(moved, "approve", "lonnrot", artifacts: AllPresent)
    on_branch(root, "moved", "lib/moved.ex", "v2")

    assert {:error, {:bounced, why}} = Workline.approve(parked(moved), artifacts: AllPresent, merge: Merges)
    assert why =~ "after its review"
    assert %Thread{stage: "build"} = Repo.get!(Thread, moved.id)
  end

  test "a landing whose code moved since its review goes back to build, unmerged", %{root: root} do
    thread = at_review(root, "queued")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, queued} = thread |> parked() |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()
    on_branch(root, "queued", "lib/queued.ex", "v2")

    assert {:error, {:bounced, _}} = Workline.land_queued(queued, merge: Merges)
    assert %Thread{stage: "build", state: "open"} = Repo.get!(Thread, thread.id)
  end

  test "a branch rebased onto a newer main since its review is the same change, and lands", %{root: root} do
    thread = at_review(root, "rebased")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, queued} = thread |> parked() |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    commit(root, "lib/elsewhere.ex", "main moved")
    git(root, ["checkout", "-q", "work/rebased"])
    git(root, ["rebase", "-q", "main"])
    git(root, ["checkout", "-q", "main"])

    assert {:ok, %{stage: "merged"}} = Workline.land_queued(queued, merge: Merges)
  end

  test "commits main took on its own drop out: the rest, rebased, is the same change", %{root: root} do
    thread = at_review(root, "absorbed")
    on_branch(root, "absorbed", "lib/absorbed_two.ex", "two")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, queued} = thread |> parked() |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    {first, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/absorbed~1"])
    git(root, ["cherry-pick", String.trim(first)])
    git(root, ["checkout", "-q", "work/absorbed"])
    git(root, ["rebase", "-q", "main"])
    git(root, ["checkout", "-q", "main"])

    assert {:ok, %{stage: "merged"}} = Workline.land_queued(queued, merge: Merges)
  end

  test "a rebase that resolved a conflict goes back to build, saying so", %{root: root} do
    thread = at_review(root, "clash")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, queued} = thread |> parked() |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    commit(root, "lib/clash.ex", "main's v1")
    git(root, ["checkout", "-q", "work/clash"])
    {_, _} = System.cmd("git", ["-C", root, "rebase", "main"], stderr_to_stdout: true)
    File.write!(Path.join(root, "lib/clash.ex"), "v1, resolved")
    git(root, ["add", "lib/clash.ex"])
    git(root, ["-c", "core.editor=true", "rebase", "--continue"])
    git(root, ["checkout", "-q", "main"])

    assert {:error, {:bounced, why}} = Workline.land_queued(queued, merge: Merges)
    assert why =~ "conflict"
  end

  test "a reviewed commit git can no longer read is a change, and is logged", %{root: root} do
    thread = at_review(root, "unreadable")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)

    Repo.update_all(
      from(e in Server.Event, where: e.thread_id == ^thread.id and e.correlation == "workline:unreadable:review"),
      set: [detail: %{"exit" => 0, "sha" => String.duplicate("0", 40)}]
    )

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, {:bounced, _}} = Workline.approve(parked(thread), artifacts: AllPresent, merge: Merges)
      end)

    assert log =~ "can't compare"
  end

  test "back at review, the last round's review.md doesn't pass it: this round needs its own verdict",
       %{root: root} do
    thread = at_review(root, "second-round")
    {:error, {:bounced, _}} = Workline.review_verdict(thread, "request_changes", "lonnrot", artifacts: AllPresent)
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
    {:ok, reviewing} = Workline.advance(verifying, artifacts: AllPresent)

    assert {:error, {:artifact_missing, why}} = Workline.advance(reviewing, artifacts: AllPresent)
    assert why =~ "this round"
    assert %Thread{stage: "review", awaiting: nil} = Repo.get!(Thread, thread.id)

    {:ok, _} = Workline.review_verdict(reviewing, "approve", "lonnrot", artifacts: AllPresent)
    assert {:awaiting, _} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
  end

  test "a bounce while the landing's gate runs wins: nothing lands, the builder keeps it", %{root: root} do
    thread = at_review(root, "bounced-mid-landing")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, queued} = thread |> parked() |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    # QA fails the workline while the landing's gate is running; the gate still comes back green
    gate = fn _repo, _branch ->
      {:error, {:bounced, _}} =
        Workline.qa_verdict(Repo.get!(Thread, thread.id), "fail", "nolan", "R doesn't reload", artifacts: AllPresent)

      {:ok, :green}
    end

    assert {:ok, _} = Workline.land_queued(queued, merge: GatedMerges, gate: gate)
    assert %Thread{stage: "build", state: "open"} = Repo.get!(Thread, thread.id)
    assert Enum.any?(Channel.thread_messages(thread), &(&1.body =~ "nothing landed"))
  end

  test "a closed workline doesn't advance", %{root: root} do
    thread = at_review(root, "closed-early")
    {:ok, _} = Workline.review_verdict(thread, "approve", "lonnrot", artifacts: AllPresent)
    {:ok, _} = Channel.close_thread(Repo.get!(Thread, thread.id))
    assert {:error, _} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
    assert %Thread{stage: "review", awaiting: nil} = Repo.get!(Thread, thread.id)
  end

  test "back at review, the reviewer is pointed at what changed since it last looked", %{root: root} do
    thread = at_review(root, "again")
    {:error, {:bounced, _}} = Workline.review_verdict(thread, "request_changes", "lonnrot", artifacts: AllPresent)
    {seen, 0} = System.cmd("git", ["-C", root, "rev-parse", "work/again"])
    on_branch(root, "again", "lib/again.ex", "v2")
    {:ok, verifying} = Workline.advance(Repo.get!(Thread, thread.id), artifacts: AllPresent)
    {:ok, _} = Workline.advance(verifying, artifacts: AllPresent)

    brief =
      thread |> Channel.thread_messages() |> Enum.map(& &1.body) |> Enum.filter(&(&1 =~ "▶ REVIEW")) |> List.last()

    assert brief =~ "#{String.trim(seen)}..work/again"
    assert brief =~ "review.md"
  end
end
