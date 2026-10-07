defmodule Server.Workline.ContinuationTest do
  # A turn that ends on a workline still owing its stage's artifact gets a `tlon` continuation on
  # the thread (the switchboard wakes the lead), at most `max_turns` between stage advances.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Message
  alias Server.Presence.Thinking
  alias Server.Repo
  alias Server.Workline
  alias Server.Workline.Continuation

  defmodule Missing do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:error, "work/x/plan.md is not committed"}
  end

  defmodule Present do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "committed"}
  end

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Workline.open(%{title: "fix the composer", slug: "composer-wrap", stage: "plan"})
    %{thread: thread}
  end

  defp continuations(thread_id) do
    Repo.all(
      from m in Message, where: m.thread_id == ^thread_id and m.author == "tlon" and like(m.body, "↻%"), order_by: m.id
    )
  end

  test "an owed artifact still missing: one continuation naming the stage and why", %{thread: t} do
    :ok = Continuation.run(t.id, artifacts: Missing)

    assert [%Message{delivered_at: nil} = m] = continuations(t.id)
    assert m.body =~ "↻ continue (1/3)"
    assert m.body =~ "plan"
    assert m.body =~ "work/x/plan.md is not committed"
  end

  test "at review the continuation says how a reviewer lands it — submit_review, not a commit it cannot make" do
    {:ok, review} = Workline.open(%{title: "review it", slug: "reviewing", stage: "review"})
    :ok = Continuation.run(review.id, artifacts: Missing)
    assert [m] = continuations(review.id)
    assert m.body =~ "submit_review"
    refute m.body =~ "Commit it"
  end

  test "at most max_turns between stage advances; an advance starts the count again", %{thread: t} do
    for _ <- 1..3, do: Continuation.run(t.id, artifacts: Missing, max_turns: 3)
    assert length(continuations(t.id)) == 3

    {:ok, _} = Workline.advance(Repo.get!(Server.Thread, t.id), artifacts: Present)
    :ok = Continuation.run(t.id, artifacts: Missing, max_turns: 3)
    assert length(continuations(t.id)) == 4
  end

  test "nudges run out: the workline stops on the operator, once, saying it is stuck and why", %{thread: t} do
    for _ <- 1..5, do: Continuation.run(t.id, artifacts: Missing, max_turns: 3)

    stuck = Repo.get!(Server.Thread, t.id)
    assert stuck.awaiting == "andrew"

    assert [m] =
             Repo.all(
               from m in Message, where: m.thread_id == ^t.id and m.author == "tlon" and like(m.body, "⚠ stuck%")
             )

    assert m.body =~ "plan" and m.body =~ "work/x/plan.md is not committed"
  end

  test "at verify the server owes the artifact: no nudge while its verify job is in flight, then one" do
    {:ok, v} = Workline.open(%{title: "verify it", slug: "verifying", stage: "verify"})
    job = Repo.insert!(Server.Jobs.Verify.new(%{thread_id: v.id, slug: v.slug}))

    for _ <- 1..5, do: :ok = Continuation.run(v.id, artifacts: Missing)
    assert continuations(v.id) == []
    assert Repo.get!(Server.Thread, v.id).awaiting == nil

    job |> Ecto.Changeset.change(state: "completed") |> Repo.update!()
    :ok = Continuation.run(v.id, artifacts: Missing)
    assert [_] = continuations(v.id)
  end

  test "where a sheriff owns red, running out of nudges goes to the sheriff — it does not wait on the operator" do
    {:ok, ws} = Server.Workspaces.register(%{name: "Sheriffed"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
    {:ok, t} = Workline.open(%{title: "stalls", slug: "stalls", stage: "plan", workspace_id: ws.id})

    for _ <- 1..5, do: Continuation.run(t.id, artifacts: Missing, max_turns: 3)

    assert Repo.get!(Server.Thread, t.id).awaiting == nil
    beat = Repo.one!(from th in Server.Thread, where: th.workspace_id == ^ws.id and th.title == "sheriff's beat")
    assert Repo.exists?(from m in Message, where: m.thread_id == ^beat.id and like(m.body, "%stuck at plan%"))
  end

  test "nothing to say: the artifact is there, the gate is parked, the thread is plain, a prompt is open",
       %{thread: t} do
    :ok = Continuation.run(t.id, artifacts: Present)

    {:ok, parked} = Workline.open(%{title: "spec it", slug: "parked", stage: "spec"})
    {:awaiting, parked} = Workline.advance(parked, artifacts: Present)
    :ok = Continuation.run(parked.id, artifacts: Missing)

    {:ok, plain} = Server.Channel.open_thread(%{title: "chat", scope: "machine"})
    :ok = Continuation.run(plain.id, artifacts: Missing)

    Repo.insert!(
      Message.post_changeset(%{thread_id: t.id, author: "tlon", body: "⚑", kind: "prompt", payload: %{"window" => "w"}})
    )

    :ok = Continuation.run(t.id, artifacts: Missing)

    assert continuations(t.id) == []
    assert continuations(parked.id) == []
    assert continuations(plain.id) == []
  end

  test "an explicit idle schedules the job; the stuck-harness sweep does not", %{thread: t} do
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, store} = Thinking.start_link(name: :continuation_thinking, max_seconds: 0, sweep_interval_ms: 60_000)

    :ok = Thinking.thinking(store, t.id, "builder")
    :ok = Thinking.sweep(store)
    refute_enqueued(worker: Server.Jobs.Continue, args: %{thread_id: t.id})

    :ok = Thinking.thinking(store, t.id, "builder")
    :ok = Thinking.idle(store, t.id, "builder")
    assert_enqueued(worker: Server.Jobs.Continue, args: %{thread_id: t.id})
  end
end
