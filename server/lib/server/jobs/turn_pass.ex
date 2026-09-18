defmodule Server.Jobs.TurnPass do
  @moduledoc """
  One memory pass over one thread, as a job (one-brain piece E, slice 2). Enqueued by
  `Server.Memory.TurnPass.schedule/1` when a turn ends (`presence_idle`); unique per thread for
  the pass's interval, so a burst of idles on one thread is one extraction, and the row survives
  a restart where the old in-memory guard did not.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 600, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  alias Server.Memory.TurnPass

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) when is_integer(tid), do: TurnPass.run(tid)
end
