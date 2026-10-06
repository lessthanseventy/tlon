defmodule Server.Jobs.Dispatch do
  @moduledoc """
  The calendar's clock, on Oban's cron every minute: fires what the operator scheduled that is due
  (`Server.Schedules.dispatch/1`). One at a time, so two ticks never race to fire the same slot.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 50, states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    _ = Server.Schedules.dispatch()
    :ok
  end
end
