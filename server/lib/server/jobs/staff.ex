defmodule Server.Jobs.Staff do
  @moduledoc """
  The staffing pass on Oban's cron, every minute (`Server.Staffing.pass/0`): cold, orphaned and
  stale coworker windows closed, a turn a machine restart cut off picked up. One at a time, so two
  passes never race over the same windows.
  """
  use Oban.Worker, queue: :staff, max_attempts: 1, unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias Server.Staffing

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Staffing.pass()
end
