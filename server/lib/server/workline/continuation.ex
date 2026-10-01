defmodule Server.Workline.Continuation do
  @moduledoc """
  A turn that ends with the workline's stage still owing its artifact is not done. When a
  harness declares idle (`presence_idle`), `schedule/1` queues `Server.Jobs.Continue`; `run/2`
  posts a `tlon` continuation on the thread — the stage, why its artifact is missing, what to do
  — and the switchboard wakes the lead with it, the same for every harness.

  Bounded: at most `max_turns` (default 3) between stage advances, so a coworker that genuinely
  cannot produce the artifact stops being pushed and `Server.Maintain.Sweep` takes it from there.
  Each continuation names the `stage_advanced` event it follows in its payload, so the count is a
  query, never a column. Silent on a plain thread, a merged one, one parked at a gate, one whose
  artifact is there, and one with a prompt open on the operator.
  """

  import Ecto.Query

  alias Server.Attention
  alias Server.Channel
  alias Server.Event
  alias Server.Jobs
  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  @default_max_turns 3

  @doc "Queue a continuation check for `thread_id`; never raises (an idle must not fail on it)."
  def schedule(thread_id) when is_integer(thread_id), do: Jobs.enqueue(Jobs.Continue.new(%{thread_id: thread_id}))

  @doc "Post a continuation when the thread's workline owes one. Opts: `artifacts:`, `max_turns:`."
  def run(thread_id, opts \\ []) do
    max = Keyword.get(opts, :max_turns, @default_max_turns)

    with %Thread{state: "open", awaiting: nil} = thread <- Repo.get(Thread, thread_id),
         {:error, why} <- Workline.owed_status(thread, opts),
         false <- Attention.waiting?(thread_id),
         after_id = last_advance_id(thread_id),
         sent when sent < max <- sent_since(thread_id, after_id) do
      Channel.post(%{
        thread_id: thread_id,
        author: "tlon",
        body:
          "↻ continue (#{sent + 1}/#{max}) — workline #{thread.slug} is at #{thread.stage} and its owed " <>
            "artifact is not there: #{why}. Commit it (then call advance_stage), or post on the thread " <>
            "why you cannot.",
        payload: %{"continue_after" => after_id}
      })

      :ok
    else
      _ -> :ok
    end
  end

  defp last_advance_id(thread_id) do
    Repo.one(
      from e in Event,
        where: e.thread_id == ^thread_id and e.kind == "stage_advanced",
        select: max(e.id)
    ) || 0
  end

  defp sent_since(thread_id, after_id) do
    Repo.aggregate(
      from(m in Message,
        where:
          m.thread_id == ^thread_id and m.author == "tlon" and
            fragment("(? ->> 'continue_after')::bigint", m.payload) == ^after_id
      ),
      :count
    )
  end
end
