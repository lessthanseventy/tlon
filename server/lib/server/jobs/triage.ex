defmodule Server.Jobs.Triage do
  @moduledoc "Hourly: brief each workspace's PM whose triage is due (`Server.Triage.run/1`)."
  use Oban.Worker, queue: :maintain, max_attempts: 1

  @impl Oban.Worker
  def perform(_job) do
    _ = Server.Triage.run()
    :ok
  end
end
