defmodule Server.Jobs.ShiftBack do
  @moduledoc """
  The reset of Claude's usage limit, scheduled when the operator took an offer to put another crew
  on (`Server.Shifts`): with that crew still on, the operator is offered the one it took off (`back`).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workspace_id" => ws, "reset" => reset} = args}),
    do: Server.Shifts.offer_back(ws, args["back"] || "day", reset, args["estimated"] == true)
end
