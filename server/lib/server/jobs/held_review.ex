defmodule Server.Jobs.HeldReview do
  @moduledoc "Weekly, Monday morning (`config/config.exs`): post the PM's review of long-held tickets (`Server.HeldReview.run/0`)."
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 3600]

  @impl Oban.Worker
  def perform(_job) do
    _ = Server.HeldReview.run()
    :ok
  end
end
