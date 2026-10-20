defmodule Server.Jobs.Orphans do
  @moduledoc """
  At boot, before Oban's queues start: a job this node left `executing` cannot be running, because
  nothing runs on a node that has only just started. It is an orphan of the restart (a release, a
  crash) and goes back to `available` to run again. Without this it would wait for Oban's
  Lifeline (`rescue_after`), which is long because a verify or a landing may legitimately wait its
  turn in the machine's checks queue first, and an orphaned landing would hold the merge queue
  (one at a time, unique while executing) for that whole time.

  Lifeline's rule, exactly: an orphan below its `max_attempts` is requeued, one at it is
  discarded. An exhausted job put back as `available` is never run — the engine's fetch picks a
  queue's oldest available jobs first and only then drops those at their limit — and, picked
  every time, it holds the slots: two of them stalled the `schedules` queue for a week (#417).
  A discarded `RunSchedule` closes its run's row as failed, saying the restart interrupted it
  (#312), so the board never shows it `running`.

  Only this node's jobs (`attempted_by` names it): another node on the same store may be running
  its own. A child of the application placed before Oban; it does its work in `start_link/1` and
  returns `:ignore`.
  """
  import Ecto.Query

  require Logger

  def child_spec(oban_opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [oban_opts]}, restart: :temporary}

  @doc false
  def start_link(oban_opts) do
    requeue(Oban.Config.new(oban_opts).node)
    :ignore
  end

  @doc """
  Put this node's `executing` jobs back to `available` when they have attempts left, discard the
  rest, in one transaction: a failure leaves every job as it was. The number requeued.
  """
  def requeue(node) do
    now = DateTime.utc_now()
    mine = from(j in Oban.Job, where: j.state == "executing" and fragment("?[1] = ?", j.attempted_by, ^node))

    {:ok, {discarded, n}} =
      Server.Repo.transaction(fn ->
        {discarded, spent} =
          mine
          |> where([j], j.attempt >= j.max_attempts)
          |> select([j], map(j, [:worker, :args]))
          |> Server.Repo.update_all(set: [state: "discarded", discarded_at: now])

        interrupt_runs(spent, now)

        {n, _} =
          Server.Repo.update_all(where(mine, [j], j.attempt < j.max_attempts),
            set: [state: "available", scheduled_at: now]
          )

        {discarded, n}
      end)

    if discarded > 0,
      do:
        Logger.warning(
          "boot: #{discarded} job(s) left executing by the last run of #{node} had no attempt left and are discarded"
        )

    if n > 0, do: Logger.info("boot: #{n} job(s) left executing by the last run of #{node} go back in their queues")
    n
  rescue
    e ->
      Logger.warning("boot: could not requeue orphaned jobs: #{Exception.message(e)}")
      0
  end

  # a discarded RunSchedule never closes its run: the row would sit at `running` forever
  defp interrupt_runs(jobs, now) do
    ids = for %{worker: "Server.Jobs.RunSchedule", args: %{"run_id" => id}} <- jobs, do: id

    if ids != [] do
      Server.Repo.update_all(from(r in Server.ScheduleRun, where: r.id in ^ids and r.status == "running"),
        set: [
          status: "failed",
          output: "interrupted: the server restarted before the run finished",
          finished_at: DateTime.truncate(now, :second)
        ]
      )
    end
  end
end
