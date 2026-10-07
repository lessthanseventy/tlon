defmodule Server.Jobs.Intake do
  @moduledoc "The backlog's intake on Oban's cron (`Server.Intake`): one ready ticket per workspace to its manager, while worklines are under the cap."
  use Oban.Worker, queue: :maintain, max_attempts: 1, unique: [period: 60]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Server.Intake.run()
end
