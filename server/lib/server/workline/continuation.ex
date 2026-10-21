defmodule Server.Workline.Continuation do
  @moduledoc """
  A turn that ends with the workline's stage still owing its artifact is not done. When a
  harness declares idle (`presence_idle`), `schedule/1` queues `Server.Jobs.Continue`; `run/2`
  posts a `tlon` continuation on the thread — the stage, why its artifact is missing, what to do
  — and the switchboard wakes the lead with it, the same for every harness.

  Bounded: at most `max_turns` (default 3) between stage advances. The third nudge of a round goes
  to a fresh session: the lead's session on the thread is rolled first (`Server.Staffing.roll_leaf/1`).
  A coworker that genuinely cannot
  produce the artifact is not pushed again: the workline stops on the operator, saying it is stuck
  and why, so it reaches them as something to decide rather than sitting quiet.
  Each continuation names the `stage_advanced` event it follows in its payload, so the count is a
  query, never a column. Silent on a plain thread, a merged one, one parked at a gate, one whose
  artifact is there, one with a prompt open on the operator, one whose smoke is still building
  (`Server.Smoke.building/2`), and while the office is paused
  (`Server.Pause`).
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

  @roll_after 2

  @doc "Queue a continuation check for `thread_id`; never raises (an idle must not fail on it)."
  def schedule(thread_id) when is_integer(thread_id), do: Jobs.enqueue(Jobs.Continue.new(%{thread_id: thread_id}))

  @doc """
  Post a continuation when the thread's workline owes one. Opts: `artifacts:`, `max_turns:`, and
  `quiet: true` from the quiet-band sweep, where a workline whose artifact is there but that has
  not moved is nudged to advance too — on an ordinary idle that is only a turn ending mid-stage.
  """
  def run(thread_id, opts \\ []) do
    max = Keyword.get_lazy(opts, :max_turns, fn -> Server.OperatorConfig.setting("continuation_turns") end)

    with :working <- Server.Pause.state(),
         %Thread{state: "open", awaiting: nil} = thread <- Repo.get(Thread, thread_id),
         {:nudge, why, say} <- nudge(thread, opts),
         false <- Attention.waiting?(thread_id),
         false <- verifying?(thread),
         nil <- Server.Smoke.building(thread_id),
         after_id = last_advance_id(thread_id),
         sent = sent_since(thread_id, after_id),
         {:budget, true, _} <- {:budget, sent < max, {thread, why, sent, after_id}} do
      # After two nudges in one context, a fresh session reading the thread beats a third push
      # into a context full of failed attempts: roll the lead first, once per stage round.
      rolled = sent == @roll_after

      if rolled, do: Server.Staffing.roll_leaf(thread)

      fresh = if rolled, do: " (a fresh session: the last #{sent} turns ended without it — read them above)", else: ""

      Channel.post(%{
        thread_id: thread_id,
        author: "tlon",
        body: "↻ continue (#{sent + 1}/#{max})#{fresh} — workline #{thread.slug} is at #{thread.stage} and #{say}",
        payload: %{"continue_after" => after_id, "rolled" => rolled}
      })

      :ok
    else
      {:budget, false, {thread, why, sent, after_id}} -> stuck(thread, why, sent, after_id)
      _ -> :ok
    end
  end

  defp nudge(thread, opts) do
    case Workline.owed_status(thread, opts) do
      {:error, why} ->
        {:nudge, why,
         "its owed artifact is not there: #{why}. #{land(thread, opts)}, or post on the thread why you cannot."}

      {:ok, have} ->
        if opts[:quiet],
          do:
            {:nudge, "#{have}, but nobody advanced it",
             "its artifact is there (#{have}) but it has not moved: if the stage's work is done, call " <>
               "advance_stage; if not, carry on, or post on the thread what is left."},
          else: :nothing

      _ ->
        :nothing
    end
  end

  # Out of nudges. Where a sheriff owns red it is the sheriff's, and the workline waits on no one
  # it doesn't (the room shows who it truly waits on); else the operator decides — answer the lead,
  # hand it to someone else, or close it. Said once per stage: the payload marks which.
  defp stuck(thread, why, sent, after_id) do
    if !stuck_said?(thread.id, after_id) and
         Workline.escalate(thread, "#{sent} nudges at #{thread.stage} without moving") == :none do
      sheriff = Server.Sheriff.of(thread.workspace_id)

      if !sheriff do
        operator = Server.OperatorConfig.operator()
        {:ok, _} = thread |> Thread.workline_stage_changeset(%{awaiting: operator}) |> Repo.update()
      end

      Channel.post(%{
        thread_id: thread.id,
        author: "tlon",
        body:
          "⚠ stuck at #{thread.stage} after #{sent} nudges: #{why}. " <>
            if(sheriff,
              do: "#{sheriff.name}, the sheriff, has it.",
              else: "It needs you — answer the lead here, hand it to someone else, or close it."
            ),
        payload: %{"stuck_after" => after_id}
      })

      Server.Sheriff.report(thread, "stuck at #{thread.stage} after #{sent} nudges: #{why}")
    end

    :ok
  end

  defp stuck_said?(thread_id, after_id) do
    Repo.exists?(
      from m in Message,
        where:
          m.thread_id == ^thread_id and m.author == "tlon" and
            fragment("(? ->> 'stuck_after')::bigint", m.payload) == ^after_id
    )
  end

  # verify's artifact is the server's own run (Jobs.Verify, ~a minute of gates): the lead can't
  # produce it, so nudging while it runs only burns the budget and flags a healthy workline stuck
  defp verifying?(%Thread{stage: "verify", id: id}) do
    Repo.exists?(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Verify" and j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("(? ->> 'thread_id')::bigint", j.args) == ^id
    )
  end

  # waiting in the merge queue: a nudge to advance would park it on the operator and drop the landing
  defp verifying?(%Thread{stage: "review"} = thread), do: Server.Office.Needs.landing?(thread)

  defp verifying?(_thread), do: false

  defp last_advance_id(thread_id) do
    Repo.one(
      from e in Event,
        where: e.thread_id == ^thread_id and e.kind == "stage_advanced",
        select: max(e.id)
    ) || 0
  end

  # an escalation hands the stage to a new lead, who gets the budget afresh
  defp sent_since(thread_id, after_id) do
    escalated =
      Repo.one(
        from m in Message,
          where: m.thread_id == ^thread_id and m.author == "tlon" and fragment("? \\? 'escalated_from'", m.payload),
          select: max(m.id)
      ) || 0

    Repo.aggregate(
      from(m in Message,
        where:
          m.thread_id == ^thread_id and m.author == "tlon" and m.id > ^escalated and
            fragment("(? ->> 'continue_after')::bigint", m.payload) == ^after_id
      ),
      :count
    )
  end

  # a reviewer cannot write files: its artifact lands through submit_review, which commits it; an
  # owed QA's lands through submit_qa, whose pass hands it on to the merge gate
  defp land(%Thread{stage: "review"} = thread, opts) do
    if Workline.qa_leads?(thread, opts),
      do: "File what you saw with submit_qa — a pass hands it to the merge gate itself",
      else: "Land it with submit_review — the server commits review.md (then call advance_stage)"
  end

  defp land(_thread, _opts), do: "Commit it (then call advance_stage)"
end
