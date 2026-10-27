defmodule Server.MCP.Tool.ReviewBranch do
  @moduledoc """
  A reviewer's verdict on a branch that is not a workline (a session's PR branch), recorded on tlon
  as yours (`Server.BranchReview`): `approve` or `request_changes` of `branch` at `sha`, the full
  commit you read. `mise run land` lands only a branch whose newest verdict approves its head (or
  that head rebased onto main and nothing else). A review runs on its own thread, in a session its
  verdict ends: from the workspace's standing thread it is refused. A workline's review is
  `submit_review`, not this.
  """
  use Server.MCP.Tool

  schema do
    field :branch, :string, required: true, description: "The branch you reviewed, e.g. local-check"
    field :sha, :string, required: true, description: "The full 40-hex commit you read: git rev-parse <branch>"
    field :verdict, :string, required: true, description: "approve | request_changes"
    field :body, :string, required: true, description: "The review — verdict first, then findings; quoted in the PR"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    if standing?(identity.thread_id) do
      fail(
        frame,
        "refused: a review runs on its own thread, in a session its verdict ends — open a thread for this PR (open_thread, lead you) and review there"
      )
    else
      record(params, identity, frame)
    end
  end

  defp standing?(thread_id) do
    case Server.Repo.get(Server.Thread, thread_id) do
      %Server.Thread{} = thread -> Server.Channel.standing?(thread)
      nil -> false
    end
  end

  defp record(params, identity, frame) do
    case Server.BranchReview.record(%{
           branch: params[:branch],
           sha: params[:sha],
           verdict: params[:verdict],
           by: identity.agent,
           body: params[:body],
           thread_id: identity.thread_id,
           repo: Server.Profiles.tlon_root()
         }) do
      {:ok, _} -> ok(frame, %{"recorded" => params[:verdict], "branch" => params[:branch], "sha" => params[:sha]})
      {:error, why} when is_binary(why) -> fail(frame, why)
      {:error, why} -> fail(frame, "not recorded: #{inspect(why)}")
    end
  end
end

defmodule Server.MCP.Tool.LandPR do
  @moduledoc """
  Hand a reviewed PR to the merge queue (`Server.PRLanding.request/3`) over MCP: what `mise run land --
  <pr>` does, for a seat whose sandbox can't reach the service's epmd. Refused unless the PR is open
  onto main from its own unprotected branch and that branch's review on tlon (`review_branch`, by
  neither the PR's author nor a builder of it) approves its head. The outcome posts on the review's thread.
  """
  use Server.MCP.Tool

  schema do
    field :pr, :integer, required: true, description: "The GitHub PR number to land"
  end

  @impl true
  def execute(params, frame) do
    case Server.PRLanding.request(Server.Profiles.tlon_root(), params[:pr]) do
      {:ok, _job} ->
        ok(frame, %{"queued" => params[:pr], "next" => "its outcome is posted on its review's thread"})

      {:error, why} when is_binary(why) ->
        fail(frame, "refused: #{why}")

      {:error, why} ->
        fail(frame, "not queued: #{inspect(why)}")
    end
  end
end
