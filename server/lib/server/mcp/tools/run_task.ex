defmodule Server.MCP.Tool.RunTask do
  @moduledoc """
  Run a long check off your own sandbox (`Server.Jobs.RunTask`): the service runs the mise task on
  the committed head of this thread's checkout and posts the result here to you by name, which wakes
  you. Commit first: what is not committed is not in the run. Your pane stays free meanwhile.
  """
  use Server.MCP.Tool

  alias Server.Jobs.RunTask

  schema do
    field :task, :string,
      required: true,
      description: "The mise task to run: one of #{Enum.join(Server.Jobs.RunTask.tasks(), ", ")}"
  end

  @impl true
  def execute(params, frame) do
    identity = Server.MCP.Identity.from_frame(frame)

    with %Server.Thread{} = thread <-
           Server.Channel.thread(identity.thread_id) || {:error, "no thread for this session"},
         {:ok, tree} <- checkout(thread),
         {:ok, job} <- RunTask.enqueue(thread.id, identity.agent, params[:task], tree) do
      ok(frame, %{
        "queued" => job.id,
        "ref" => String.slice(job.args.ref, 0, 7),
        "next" => "the result posts on thread ##{thread.id}, addressed to you; carry on meanwhile"
      })
    else
      {:error, why} -> fail(frame, why)
    end
  end

  defp checkout(thread) do
    case Server.worktree_for_thread(thread) do
      {:ok, tree} -> {:ok, tree}
      {:error, why} -> {:error, "thread ##{thread.id} has no checkout to run in (#{inspect(why)})"}
    end
  end
end
