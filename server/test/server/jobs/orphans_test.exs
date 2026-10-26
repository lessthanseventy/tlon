defmodule Server.Jobs.OrphansTest do
  # At boot, what this node left executing goes back in its queue; another node's is left alone.
  # Oban's Lifeline rule: a job below max_attempts is requeued, one at it is discarded — an
  # exhausted job put back as available is never run and, picked first, blocks its queue (#417).
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Jobs.Orphans

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    :ok
  end

  defp executing(node, attrs \\ %{}) do
    changeset = Map.get(attrs, :changeset) || Server.Jobs.Land.new(%{thread_id: System.unique_integer([:positive])})
    {:ok, job} = Oban.insert(changeset)

    Server.Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [
        state: "executing",
        attempt: Map.get(attrs, :attempt, 1),
        attempted_by: [node, "landing"],
        attempted_at: DateTime.utc_now()
      ]
    )

    job.id
  end

  test "this node's executing jobs are requeued at boot; another node's keep running" do
    mine = executing("funes@here")
    theirs = executing("other@there")

    assert Orphans.requeue("funes@here") == 1
    assert %{state: "available"} = Server.Repo.get!(Oban.Job, mine)
    assert %{state: "executing"} = Server.Repo.get!(Oban.Job, theirs)
  end

  test "an orphan at its last attempt is discarded, not requeued; one below it is requeued" do
    # Land has max_attempts 3
    spent = executing("funes@here", %{attempt: 3})
    left = executing("funes@here", %{attempt: 2})

    assert Orphans.requeue("funes@here") == 1
    assert %{state: "discarded", discarded_at: %DateTime{}} = Server.Repo.get!(Oban.Job, spent)
    assert %{state: "available", attempt: 2} = Server.Repo.get!(Oban.Job, left)
  end

  test "the schedules queue dispatches the run behind an exhausted orphan" do
    # RunSchedule has max_attempts 1 and the queue 2 slots: two exhausted orphans ahead of a real
    # run are always the two the engine picks and drops, so the real one never runs.
    ws = %{name: "Machine"} |> Server.Workspaces.register() |> elem(1)

    run! = fn ->
      {:ok, s} =
        Server.Schedules.create(%{workspace_id: ws.id, kind: "script", title: "t", body: "true", cron: "@daily"})

      Server.Repo.insert!(%Server.ScheduleRun{
        schedule_id: s.id,
        status: "running",
        started_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end

    [a, b, c] = Enum.map(1..3, fn _ -> run!.() end)
    orphan_a = executing("funes@here", %{changeset: Server.Jobs.RunSchedule.new(%{run_id: a.id})})
    orphan_b = executing("funes@here", %{changeset: Server.Jobs.RunSchedule.new(%{run_id: b.id})})
    {:ok, real} = Oban.insert(Server.Jobs.RunSchedule.new(%{run_id: c.id}))

    assert Orphans.requeue("funes@here") == 0

    conf = Oban.config()
    {:ok, meta} = Oban.Engines.Basic.init(conf, queue: "schedules", limit: 2)
    {:ok, {_meta, fetched}} = Oban.Engines.Basic.fetch_jobs(conf, meta, %{})
    assert Enum.map(fetched, & &1.id) == [real.id]

    for id <- [orphan_a, orphan_b], do: assert(%{state: "discarded"} = Server.Repo.get!(Oban.Job, id))
  end

  test "a discarded run's row closes as interrupted" do
    ws = %{name: "Machine"} |> Server.Workspaces.register() |> elem(1)
    {:ok, s} = Server.Schedules.create(%{workspace_id: ws.id, kind: "script", title: "t", body: "true", cron: "@daily"})

    run =
      Server.Repo.insert!(%Server.ScheduleRun{
        schedule_id: s.id,
        status: "running",
        started_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    executing("funes@here", %{changeset: Server.Jobs.RunSchedule.new(%{run_id: run.id})})

    Orphans.requeue("funes@here")

    assert %{status: "interrupted", output: "interrupted: " <> _, finished_at: %DateTime{}} =
             Server.Repo.get!(Server.ScheduleRun, run.id)
  end

  test "a failure closing a discarded run leaves the discard uncommitted" do
    spent = executing("funes@here", %{attempt: 1, changeset: Server.Jobs.RunSchedule.new(%{run_id: "not-an-id"})})

    assert Orphans.requeue("funes@here") == 0
    assert %{state: "executing", discarded_at: nil} = Server.Repo.get!(Oban.Job, spent)
  end
end
