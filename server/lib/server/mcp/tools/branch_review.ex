defmodule Server.MCP.Tool.ReviewBranch do
  @moduledoc """
  A reviewer's verdict on a branch that is not a workline (a session's PR branch), recorded on tlon
  as yours (`Server.BranchReview`): `approve` or `request_changes` of `branch` at `sha`, the full
  commit you read. `mise run land` lands only a branch whose newest verdict approves its head (or
  that head rebased onto main and nothing else). A workline's review is `submit_review`, not this.
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
