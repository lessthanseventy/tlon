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
  denied). Identity-bound to THIS thread, refused outside the review stage. The `verdict`
  is recorded too (`Server.Workline.review_verdict/3`): `request_changes` sends the workline back
  to build at once; after `approve`, call advance_stage to hand it to the merge gate.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline.Review

  schema do
    field :verdict, :string, required: true, description: "approve | request_changes"
    field :body, :string, required: true, description: "The full review.md content — verdict first, then findings"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{} = thread <- Channel.thread(identity.thread_id) || {:error, :no_thread},
         :ok <- known_verdict(params[:verdict]),
         {:ok, rel} <- Review.submit(thread, params[:body], identity.agent) do
      case Server.Workline.review_verdict(thread, params[:verdict], identity.agent) do
        {:ok, _} ->
          ok(frame, %{"committed" => rel, "verdict" => "approve", "next" => "call advance_stage"})

        {:error, {:bounced, _}} ->
          ok(frame, %{"committed" => rel, "verdict" => "request_changes", "next" => "sent back to build"})

        {:error, reason} ->
          fail(frame, "verdict not recorded: #{inspect(reason)}")
      end
    else
      {:error, {:bad_verdict, v}} -> fail(frame, "verdict must be approve or request_changes, not #{inspect(v)}")
      {:error, {:not_in_review, stage}} -> fail(frame, "not in review — this workline is at #{stage}")
      {:error, reason} -> fail(frame, "submit_review failed: #{inspect(reason)}")
    end
  end

  defp known_verdict(v) when v in ~w(approve request_changes), do: :ok
  defp known_verdict(v), do: {:error, {:bad_verdict, v}}
end
