defmodule Server.Jobs.AutoResume do
  @moduledoc """
  Ends an auto pause (`Server.Pause.auto/1`) when its plan window resets: scheduled at the window's
  `resets_at`, it calls `Server.Pause.auto_resume/2`, which resumes only if the pause is still that
  one.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"window" => window, "resets_at" => resets_at}}) do
    _ = Server.Pause.auto_resume(window, resets_at)
    :ok
  end
end
