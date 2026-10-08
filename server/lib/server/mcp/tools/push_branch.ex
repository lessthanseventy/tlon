defmodule Server.MCP.Tool.PushBranch do
  @moduledoc """
  Push the caller's own thread branch, `work/<slug>`, to origin with `--force-with-lease`
  (`Server.Workline.Publish.push_branch/3`). The branch comes from the session's thread, never a
  parameter, so a coworker can push only its own; a pane's own `git push` is refused by the
  pre-push hook.
  """
  use Server.MCP.Tool

  alias Server.Workline.Publish

  schema do
  end

  @impl true
  def execute(_params, frame) do
    with %Server.Thread{} = thread <- Server.Repo.get(Server.Thread, Identity.from_frame(frame).thread_id),
         {:ok, repo} <- Server.repo_for_thread(thread),
         branch = Server.Worktree.branch(Server.Worktree.name_for(thread)),
         :ok <- Publish.push_branch(repo, branch) do
      ok(frame, %{"pushed" => branch})
    else
      nil -> fail(frame, "no thread bound to this session")
      {:error, why} -> fail(frame, to_string(why))
    end
  end
end
