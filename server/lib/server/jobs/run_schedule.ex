defmodule Server.Jobs.RunSchedule do
  @moduledoc """
  One firing of a schedule (`Server.Schedules.perform/1`): the agent run, workline or script its
  run row stands for. The run says how it went, so a script that exits non-zero is still a job
  that did its work — the rack's failed jobs are the service's failures, not the operator's
  scripts'. Never retried: a script that ran once must not run twice.
  """
  use Oban.Worker, queue: :schedules, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_id" => id}}) when is_integer(id) do
    _ = Server.Schedules.perform(id)
    :ok
  end
end
