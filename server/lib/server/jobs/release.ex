defmodule Server.Jobs.Release do
  @moduledoc """
  The PM's release work off the request path (`Server.Release.PM`): `decide` grades a proposal
  (a model call per commit) and cuts it or opens the gate; `cut` moves the pointer and builds,
  which takes minutes. Each outcome is posted on the workspace's root thread.
  """
  # One attempt: a cut restarts the server, and Lifeline must never run a cut a second time.
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 600, keys: [:action, :sha], states: [:available, :scheduled, :executing]]

  alias Server.Release.PM

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => action, "workspace_id" => ws, "sha" => sha} = args}) do
    _ =
      case action do
        "decide" -> PM.decide(ws, sha, args["notes"])
        "cut" -> PM.cut(ws, sha, args["notes"])
      end

    :ok
  end
end
