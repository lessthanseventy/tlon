defmodule Server.MCP.Tool.PushBranch do
  @moduledoc """
  Push the caller's own thread branch, `work/<slug>`, to origin with `--force-with-lease`
  (`Server.Workline.Publish.push_branch/3`). The branch is the session's thread's, or with
  `thread_id` that of a thread the caller leads, so a coworker can push only its own; a pane's own
  `git push` is refused by the pre-push hook. With `branch`, a named `work/<caller's handle>-<name>`
  instead (a seat with no thread branch, such as Uqbar): never another's prefix, never a workline's slug.
  """
  use Server.MCP.Tool

  alias Server.Workline.Publish

  schema do
    field :thread_id, :integer,
      description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"

    field :branch, :string,
      description: "Push this branch instead of the thread's own; only `work/<your handle>-<name>` is allowed"
  end

  @impl true
  def execute(params, frame) do
    with %Server.Thread{} = thread <- acting_thread(params, frame),
         {:ok, branch} <- branch_to_push(params, thread, frame),
         {:ok, repo} <- Server.repo_for_thread(thread),
         :ok <- Publish.push_branch(repo, branch) do
      ok(frame, %{"pushed" => branch})
    else
      {:error, why} -> fail(frame, to_string(why))
    end
  end

  defp branch_to_push(%{branch: branch}, _thread, frame) when is_binary(branch) do
    with :ok <- Publish.own_branch(Server.MCP.Identity.from_frame(frame).agent, branch),
         :ok <- not_a_workline(branch),
         do: {:ok, branch}
  end

  defp branch_to_push(_params, thread, _frame), do: {:ok, Server.Worktree.branch(Server.Worktree.name_for(thread))}

  # A slug is not always numeric, so a seat's name can prefix a workline's own branch, which a named
  # push would overwrite.
  defp not_a_workline("work/" <> slug = branch) do
    if Server.Repo.get_by(Server.Thread, slug: slug),
      do: {:error, "#{branch} is a workline's branch — push it from its own thread"},
      else: :ok
  end
end
