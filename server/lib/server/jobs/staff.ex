defmodule Server.Jobs.Staff do
  @moduledoc """
  The staffing pass on Oban's cron, every minute (one-brain piece B, slice 3): the centre, the
  tail and the leaves of every workspace, spawned by the service with no cockpit open. One at a
  time — the pass waits on harness boots, so a second must never overlap it.
  """
  use Oban.Worker, queue: :staff, max_attempts: 1, unique: [period: 300, states: [:available, :scheduled, :executing]]

  alias Server.Staffing

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Staffing.pass()
end
