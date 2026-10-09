defmodule Server.Jobs.ShiftBack do
  @moduledoc """
  The reset of Claude's usage limit, scheduled when the limit put the night shift on
  (`Server.Shifts`): still on nights, the operator is asked whether to put the day crew back.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workspace_id" => ws, "reset" => reset}}), do: Server.Shifts.offer_day(ws, reset)
end
