defmodule Server.Jobs.Grade do
  @moduledoc """
  A reviewed workline's risk grade (`Server.Workline.Grade`), off the request path: the grader is a
  model call that can take minutes. Enqueued when a reviewer approves; once the grade is on record,
  `Server.Workline.graded/2` lands a gate already parked on the operator that the grade lets through.
  A thread that has left review since is not graded.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 600, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) do
    case Server.Repo.get(Server.Thread, tid) do
      %Server.Thread{stage: "review", state: "open"} = thread ->
        Server.Workline.Grade.grade(thread)
        {:ok, _} = Server.Workline.graded(thread)
        :ok

      _ ->
        :ok
    end
  end
end
