defmodule Server.Jobs.Continue do
  @moduledoc """
  One continuation check on one thread (`Server.Workline.Continuation`), enqueued when a turn
  ends. Unique per thread for a short window, so an idle declared twice is one check.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 30, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  alias Server.Workline.Continuation

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) when is_integer(tid), do: Continuation.run(tid)
end
