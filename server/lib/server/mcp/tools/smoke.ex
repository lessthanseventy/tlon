defmodule Server.MCP.Tool.StartSmoke do
  @moduledoc """
  QA's door to a scratch release (`Server.Smoke`): the service builds the branch, smokes it and
  holds it up, then posts its url on the thread. A seat's own Bash can't run
  `release:smoke` (it needs Postgres's socket), so QA asks here. Lands on THIS thread, or on
  `thread_id` — the workline QA'd — when the caller is a `qa` seat on that workline's bench.
  """
  use Server.MCP.Tool

  alias Server.Smoke

  schema do
    field :thread_id, :integer,
      description: "The workline you QA (its #id), when your session is bound to another thread"

    field :ref, :string, description: "The ref to smoke (default: the workline's branch, work/<slug>)"

    field :flags, {:list, :string},
      description: "Feature flags to turn on in the smoke's own database (e.g. [\"build_mode\"]) for a flagged path"
  end

  @impl true
  def execute(params, frame) do
    with {:ok, thread} <- Server.MCP.Tool.QASmoke.thread(params, frame),
         {:ok, job} <-
           Smoke.start(thread, params[:ref], Server.MCP.Identity.from_frame(frame).agent, params[:flags] || []) do
      ok(frame, %{
        "queued" => job.id,
        "next" => "the url is posted on thread ##{thread.id} when the build is up (minutes)"
      })
    else
      {:error, why} -> fail(frame, why)
    end
  end
end

defmodule Server.MCP.Tool.DriveSmoke do
  @moduledoc """
  Drive the held smoke from the service (`Server.Smoke.drive/2`): each key is one
  `office:drive` step (the drive-office skill), the screen after each comes back. Your own Bash
  can't reach the smoke's port, so the drive runs here.
  """
  use Server.MCP.Tool

  alias Server.Smoke

  schema do
    field :keys, {:list, :string}, required: true, description: ~s(office:drive steps, e.g. ["wait:HOME", "/", "Enter"])

    field :thread_id, :integer,
      description: "The workline you QA (its #id), when your session is bound to another thread"
  end

  @impl true
  def execute(params, frame) do
    with {:ok, thread} <- Server.MCP.Tool.QASmoke.thread(params, frame),
         {:ok, screens} <- Smoke.drive(thread.id, params[:keys]) do
      ok(frame, %{"screens" => screens})
    else
      {:error, why} -> fail(frame, why)
    end
  end
end

defmodule Server.MCP.Tool.StopSmoke do
  @moduledoc "Tear down the thread's held smoke (`Server.Smoke.stop/1`)."
  use Server.MCP.Tool

  alias Server.Smoke

  schema do
    field :thread_id, :integer,
      description: "The workline you QA (its #id), when your session is bound to another thread"
  end

  @impl true
  def execute(params, frame) do
    with {:ok, thread} <- Server.MCP.Tool.QASmoke.thread(params, frame),
         :ok <- Smoke.stop(thread.id) do
      ok(frame, %{"stopping" => true})
    else
      {:error, why} -> fail(frame, why)
    end
  end
end

defmodule Server.MCP.Tool.QASmoke do
  @moduledoc false

  @doc "The thread a smoke tool acts on: the session's own, or the workline of a bench this `qa` seat sits on."
  def thread(params, frame) do
    identity = Server.MCP.Identity.from_frame(frame)
    id = params[:thread_id] || identity.thread_id

    case Server.Channel.thread(id) do
      nil ->
        {:error, "no such thread: #{id}"}

      thread ->
        if id == identity.thread_id or qa_seat?(thread, identity.agent),
          do: {:ok, thread},
          else: {:error, "#{identity.agent} is not a qa seat on thread #{id}'s bench"}
    end
  end

  defp qa_seat?(%{workspace_id: nil}, _agent), do: false

  defp qa_seat?(thread, agent),
    do: thread.workspace_id |> Server.Workspaces.bench() |> Enum.any?(&(&1.archetype == "qa" and &1.name == agent))
end
