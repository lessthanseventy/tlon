defmodule Server.Jobs.Maintain do
  @moduledoc """
  The Maintain sweeps on Oban's cron (one-brain piece E, slice 2): every half hour, stale
  gates get their reminder and stalled worklines their machine-born flag. `args` may name a
  band in ms (`gate_stale_ms`, `stalled_ms`, `renag_ms`) — tests do; the cron entry passes none.
  """
  use Oban.Worker, queue: :maintain, max_attempts: 1, unique: [period: 60]

  alias Server.Maintain.Sweep

  @bands ~w(gate_stale_ms stalled_ms renag_ms)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    opts = for {k, v} <- args, k in @bands, is_integer(v), do: {String.to_existing_atom(k), v}
    Sweep.run(opts)
  end
end
