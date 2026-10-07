defmodule Server.Workline.Continuation do
  @moduledoc """
  A turn that ends with the workline's stage still owing its artifact is not done. When a
  harness declares idle (`presence_idle`), `schedule/1` queues `Server.Jobs.Continue`; `run/2`
  posts a `tlon` continuation on the thread — the stage, why its artifact is missing, what to do
  — and the switchboard wakes the lead with it, the same for every harness.

  Bounded: at most `max_turns` (default 3) between stage advances. A coworker that genuinely cannot
  produce the artifact is not pushed again: the workline stops on the operator, saying it is stuck
  and why, so it reaches them as something to decide rather than sitting quiet.
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
         sent = sent_since(thread_id, after_id),
         {:budget, true, _} <- {:budget, sent < max, {thread, why, sent}} do
      Channel.post(%{
        thread_id: thread_id,
        author: "tlon",
        body:
          "↻ continue (#{sent + 1}/#{max}) — workline #{thread.slug} is at #{thread.stage} and its owed " <>
            "artifact is not there: #{why}. #{land(thread.stage)}, or post on the thread " <>
            "why you cannot.",
        payload: %{"continue_after" => after_id}
      })

      :ok
    else
      {:budget, false, {thread, why, sent}} -> stuck(thread, why, sent)
      _ -> :ok
    end
  end

  # out of nudges: the operator decides — answer the lead, hand it to someone else, or close it
  defp stuck(thread, why, sent) do
    operator = Application.get_env(:server, :operator, "andrew")
    {:ok, _} = thread |> Thread.workline_stage_changeset(%{awaiting: operator}) |> Repo.update()

    Channel.post(%{
      thread_id: thread.id,
      author: "tlon",
      body:
        "⚠ stuck at #{thread.stage} after #{sent} nudges: #{why}. It needs you — answer the lead here, " <>
          "hand it to someone else, or close it."
    })

    :ok
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

  # a reviewer cannot write files: its artifact lands through submit_review, which commits it
  defp land("review"), do: "Land it with submit_review — the server commits review.md (then call advance_stage)"
  defp land(_stage), do: "Commit it (then call advance_stage)"
end
