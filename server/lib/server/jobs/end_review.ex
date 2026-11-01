defmodule Server.Jobs.EndReview do
  @moduledoc """
  Ends a reviewer's throwaway session once its verdict has moved the thread
  (`Server.Staffing.end_review/1`), off the request path. Closing the reviewer's window takes its
  client down, and the client's teardown cancels the request still running on the server (anubis:
  `notifications/cancelled` terminates the tool call's task, a session DELETE stops its process), so
  nothing the verdict owes — the park, the bounce, the follow-ups — may run after the window goes in
  that request. Enqueued last by `Server.Workline.review_verdict/4`; a thread gone since ends nothing.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) do
    case Server.Repo.get(Server.Thread, tid) do
      %Server.Thread{} = thread -> Server.Staffing.end_review(thread)
      nil -> :ok
    end
  end
end
