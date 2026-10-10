defmodule Server.MCP.Tool.AdvanceStage do
  @moduledoc """
  Advance THIS thread's workline past its current stage (worklines slice 1) — the single
  sanctioned mutation. Refused without the stage's owed artifact COMMITTED (the check lands
  in CHECKS either way); gated transitions (spec→plan, review→merged, machine-born intent)
  park `awaiting: andrew` — the operator approves, an agent never can. You advance the workline
  you are standing on, or with `thread_id` one you lead (`Server.MCP.Tool.acting_thread/2`).
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline

  schema do
    field :thread_id, :integer,
      description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"
  end

  @impl true
  def execute(params, frame) do
    case acting_thread(params, frame) do
      {:error, why} -> fail(frame, why)
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
  denied). On THIS thread, or with `thread_id` one you lead; refused outside the review stage. The `verdict`
  is recorded too (`Server.Workline.review_verdict/3`): `request_changes` sends the workline back
  to build at once; after `approve`, call advance_stage to hand it to the merge gate. A finding that
  shouldn't block goes in `follow_ups`: each becomes a ticket held until the workline merges.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline.Review

  schema do
    field :verdict, :string, required: true, description: "approve | request_changes"
    field :body, :string, required: true, description: "The full review.md content — verdict first, then findings"

    field :thread_id, :integer,
      description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"

    field :follow_ups, {:list, :string},
      description:
        "Findings that shouldn't block this change, one per entry: first line the title, the rest the detail. Each becomes a ticket, held until the workline merges. This list REPLACES the follow-ups an earlier review of this workline filed: list every non-blocking finding still open, not only new ones"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{} = thread <- acting_thread(params, frame),
         :ok <- known_verdict(params[:verdict]),
         {:ok, rel} <- Review.submit(thread, params[:body], identity.agent) do
      {:ok, filed} = Server.Workline.follow_ups(thread, identity.agent, params[:follow_ups] || [])

      case Server.Workline.review_verdict(thread, params[:verdict], identity.agent) do
        {:ok, _} ->
          ok(frame, %{
            "committed" => rel,
            "verdict" => "approve",
            "follow_ups" => length(filed),
            "next" => "call advance_stage"
          })

        {:error, {:bounced, _}} ->
          ok(frame, %{
            "committed" => rel,
            "verdict" => "request_changes",
            "follow_ups" => length(filed),
            "next" => "sent back to build"
          })

        {:error, reason} ->
          fail(frame, "verdict not recorded: #{inspect(reason)}")
      end
    else
      {:error, {:bad_verdict, v}} -> fail(frame, "verdict must be approve or request_changes, not #{inspect(v)}")
      {:error, {:not_in_review, stage}} -> fail(frame, "not in review — this workline is at #{stage}")
      {:error, why} when is_binary(why) -> fail(frame, why)
      {:error, reason} -> fail(frame, "submit_review failed: #{inspect(reason)}")
    end
  end

  defp known_verdict(v) when v in ~w(approve request_changes), do: :ok
  defp known_verdict(v), do: {:error, {:bad_verdict, v}}
end

defmodule Server.MCP.Tool.SubmitQA do
  @moduledoc """
  QA's door (roster design §5): after driving a reviewed user-visible change on a scratch release,
  file what you saw — `pass`, or `fail` with the finding (`Server.Workline.qa_verdict/5`). A fail
  sends the workline back to build with your report; a pass moves it to the merge gate.
  Lands on THIS thread, or on `thread_id` — the workline QA'd — when the caller is a `qa` seat on
  that workline's bench: a QA session can be bound to another thread (the lobby) than the one it
  was called to. Refused outside the review stage. A finding that shouldn't block goes in
  `follow_ups`: each becomes a ticket held until the workline merges.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline

  schema do
    field :verdict, :string, required: true, description: "pass | fail"

    field :report, :string,
      required: true,
      description: "What you pressed and the screen text you saw; for a fail, the one thing that is wrong"

    field :thread_id, :integer,
      description: "The workline you QA'd (its #id), when your session is bound to another thread"

    field :follow_ups, {:list, :string},
      description:
        "Findings that shouldn't block this change, one per entry: first line the title, the rest the detail. Each becomes a ticket, held until the workline merges. This list REPLACES the follow-ups an earlier QA pass of this workline filed: list every finding still open"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    thread_id = params[:thread_id] || identity.thread_id

    case Channel.thread(thread_id) do
      nil ->
        fail(frame, "no such thread: #{thread_id}")

      thread ->
        if thread_id == identity.thread_id or qa_seat?(thread, identity.agent),
          do: verdict(thread, params, identity.agent, frame),
          else: fail(frame, "#{identity.agent} is not a qa seat on thread #{thread_id}'s bench")
    end
  end

  defp qa_seat?(%{workspace_id: nil}, _agent), do: false

  defp qa_seat?(thread, agent),
    do: thread.workspace_id |> Server.Workspaces.bench() |> Enum.any?(&(&1.archetype == "qa" and &1.name == agent))

  defp verdict(thread, params, agent, frame) do
    {:ok, filed} =
      if thread.stage == "review" and params[:verdict] in ~w(pass fail),
        do: Workline.follow_ups(thread, agent, params[:follow_ups] || [], :qa),
        else: {:ok, []}

    n = length(filed)

    case Workline.qa_verdict(thread, params[:verdict], agent, params[:report]) do
      {:error, {:bounced, _}} ->
        ok(frame, %{"verdict" => "fail", "follow_ups" => n, "next" => "sent back to build"})

      {:error, {:bad_verdict, v}} ->
        fail(frame, "verdict must be pass or fail, not #{inspect(v)}")

      {:error, {:not_in_review, stage}} ->
        fail(frame, "not in review — this workline is at #{stage}")

      {:error, reason} ->
        fail(frame, "QA passed, but it could not move on: #{inspect(reason)}")

      {_, moved} ->
        ok(frame, %{"verdict" => "pass", "follow_ups" => n, "stage" => moved.stage, "awaiting" => moved.awaiting})
    end
  end
end

defmodule Server.MCP.Tool.SendBack do
  @moduledoc """
  Send a workline back to an earlier stage, on the same thread and branch — what was built and
  reviewed stays, and the stage's lead improves it rather than starting over
  (`Server.Workline.send_back/4`). Back to build: the workline's lead. Back to plan or spec: the tech
  lead only, since it reshapes the build; anyone else is told to ask him.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Workline

  schema do
    field :stage, :enum, values: ["spec", "plan", "build"], required: true, description: "The stage to send it back to"
    field :why, :string, required: true, description: "What is wrong, so the stage's lead knows what to change"

    field :thread_id, :integer,
      description: "The workline (its #id), when it isn't the thread your session is bound to (e.g. the lobby)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{stage: stage} = thread when not is_nil(stage) <-
           Channel.thread(params[:thread_id] || identity.thread_id) || {:error, "no such thread"},
         {:ok, back} <- Workline.send_back(thread, params[:stage], params[:why], identity.agent) do
      ok(frame, %{"thread_id" => back.id, "stage" => back.stage, "lead" => Channel.thread_lead(back.id)})
    else
      %Server.Thread{} ->
        fail(frame, "send_back refused: that thread is not a workline")

      {:error, {:not_movable, "merged"}} ->
        fail(frame, "send_back refused: it merged; a merged workline relands instead")

      {:error, {:not_movable, stage}} ->
        fail(frame, "send_back refused: a workline at #{stage} has nothing behind it to go back to")

      {:error, {:in_flight, why}} ->
        fail(frame, "send_back refused: #{why}")

      {:error, {:not_behind, to}} ->
        fail(frame, "send_back refused: #{to} is not a working stage behind this one")

      {:error, {:not_yours, why}} ->
        fail(frame, "send_back refused: #{why}")

      {:error, why} ->
        fail(frame, "send_back refused: #{inspect(why)}")
    end
  end
end
