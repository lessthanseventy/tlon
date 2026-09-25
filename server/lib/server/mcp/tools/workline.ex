defmodule Server.MCP.Tool.AdvanceStage do
  @moduledoc """
  Advance THIS thread's workline past its current stage (worklines slice 1) — the single
  sanctioned mutation. Refused without the stage's owed artifact COMMITTED (the check lands
  in CHECKS either way); gated transitions (spec→plan, review→merged, machine-born intent)
  park `awaiting: andrew` — the operator approves, an agent never can. Identity-bound: no
  thread parameter, you advance the workline you are standing on.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline

  schema do
  end

  @impl true
  def execute(_params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    case Channel.thread(thread_id) do
      nil -> fail(frame, "no such thread: #{thread_id}")
      thread -> advanced(Workline.advance(thread), frame)
    end
  end

  defp advanced({:ok, thread}, frame), do: ok(frame, %{"stage" => thread.stage, "awaiting" => thread.awaiting})

  defp advanced({:awaiting, thread}, frame) do
    ok(frame, %{
      "stage" => thread.stage,
      "awaiting" => thread.awaiting,
      "note" => "gated — the operator approves this transition"
    })
  end

  defp advanced({:error, {:artifact_missing, why}}, frame), do: fail(frame, "owed artifact missing: #{why}")
  defp advanced({:error, reason}, frame), do: fail(frame, "cannot advance: #{inspect(reason)}")
end

defmodule Server.MCP.Tool.SubmitReview do
  @moduledoc """
  The write-fenced reviewer's ONE door (worklines slice 3): server writes and commits
  work/<slug>/review.md itself — the reviewer profile structurally cannot (write/edit
  denied). Identity-bound to THIS thread, refused outside the review stage. Verdict at
  the top of the body; then call advance_stage to hand the merge gate to the operator.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline.Review

  schema do
    field :body, :string, required: true, description: "The full review.md content — verdict first, then findings"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{} = thread <- Channel.thread(identity.thread_id) || {:error, :no_thread},
         {:ok, rel} <- Review.submit(thread, params[:body], identity.agent) do
      ok(frame, %{"committed" => rel})
    else
      {:error, {:not_in_review, stage}} -> fail(frame, "not in review — this workline is at #{stage}")
      {:error, reason} -> fail(frame, "submit_review failed: #{inspect(reason)}")
    end
  end
end
