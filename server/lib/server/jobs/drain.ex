defmodule Server.Jobs.Drain do
  @moduledoc """
  The switchboard's durability path as a recurring job (one-brain piece E, slice 1): every
  undelivered message is offered to whoever is live now, oldest first, coalesced per pane. It ran
  only on boot before; on Oban's cron it runs every minute, so a message posted while its
  recipient was cold is delivered the moment a session appears. Idempotent — `drain/0` claims
  atomically, so a concurrent live delivery can never double-poke.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 30]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    _ = Server.Switchboard.drain()
    :ok
  end
end
