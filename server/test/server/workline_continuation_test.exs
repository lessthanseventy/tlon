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

  test "at most max_turns between stage advances; an advance starts the count again", %{thread: t} do
    for _ <- 1..5, do: Continuation.run(t.id, artifacts: Missing, max_turns: 3)
    assert length(continuations(t.id)) == 3

    {:ok, _} = Workline.advance(Repo.get!(Server.Thread, t.id), artifacts: Present)
    :ok = Continuation.run(t.id, artifacts: Missing, max_turns: 3)
    assert length(continuations(t.id)) == 4
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
