defmodule Server.MCP.Tool.PushBranch do
  @moduledoc """
  Push the caller's own thread branch, `work/<slug>`, to origin with `--force-with-lease`
  (`Server.Workline.Publish.push_branch/3`). The branch is the session's thread's, or with
  `thread_id` that of a thread the caller leads, so a coworker can push only its own; a pane's own
  `git push` is refused by the pre-push hook.
  """
  use Server.MCP.Tool

  alias Server.Workline.Publish

  schema do
    field :thread_id, :integer,
      description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"
  end

  @impl true
  def execute(params, frame) do
    with %Server.Thread{} = thread <- acting_thread(params, frame),
         {:ok, repo} <- Server.repo_for_thread(thread),
         branch = Server.Worktree.branch(Server.Worktree.name_for(thread)),
         :ok <- Publish.push_branch(repo, branch) do
      ok(frame, %{"pushed" => branch})
    else
      {:error, why} -> fail(frame, to_string(why))
    end
  end
end
