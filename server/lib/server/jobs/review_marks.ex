defmodule Server.Jobs.ReviewMarks do
  @moduledoc "The review marks' sweep on Oban's cron, every minute (`Server.ReviewMarks.sweep/1`)."
  use Oban.Worker, queue: :staff, max_attempts: 1, unique: [period: 300, states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Server.ReviewMarks.sweep()
end
