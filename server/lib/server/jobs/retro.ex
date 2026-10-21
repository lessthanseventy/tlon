defmodule Server.Jobs.Retro do
  @moduledoc """
  A landed workline's retro (`Server.Workline.Retro`), off the landing's path: a model call that can
  take a minute. Enqueued when a workline lands; one never sent back to build banks nothing.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:thread_id]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) do
    with %Server.Thread{} = thread <- Server.Repo.get(Server.Thread, tid),
         do: Server.Workline.Retro.run(thread)

    :ok
  end
end
