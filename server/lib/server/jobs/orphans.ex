defmodule Server.Jobs.Orphans do
  @moduledoc """
  At boot, before Oban's queues start: a job this node left `executing` cannot be running, because
  nothing runs on a node that has only just started. It is an orphan of the restart (a release, a
  crash) and goes back to `available` to run again. Without this it would wait for Oban's
  Lifeline (`rescue_after`), which is long because a verify or a landing may legitimately wait its
  turn in the machine's checks queue first, and an orphaned landing would hold the merge queue
  (one at a time, unique while executing) for that whole time.

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

  @doc "Put this node's `executing` jobs back to `available`. The number requeued."
  def requeue(node) do
    {n, _} =
      Server.Repo.update_all(
        from(j in Oban.Job, where: j.state == "executing" and fragment("?[1] = ?", j.attempted_by, ^node)),
        set: [state: "available", scheduled_at: DateTime.utc_now()]
      )

    if n > 0, do: Logger.info("boot: #{n} job(s) left executing by the last run of #{node} go back in their queues")
    n
  rescue
    e ->
      Logger.warning("boot: could not requeue orphaned jobs: #{Exception.message(e)}")
      0
  end
end
