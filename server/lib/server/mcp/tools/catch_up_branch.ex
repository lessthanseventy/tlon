defmodule Server.MCP.Tool.CatchUpBranch do
  @moduledoc """
  Bring the caller's thread checkout onto origin/main, run by the service because a seat's sandbox
  cannot (`.claude/settings.json` is a bind mount, so its own `git rebase` dies half-way). A clean
  branch behind main is fast-forwarded, one with commits of its own is rebased, a dirty or half-done
  checkout is refused with the reason (`Server.Worktree.bring_to_main/1`). The thread is the session's
  own, or with `thread_id` one the caller leads. Push afterwards with push_branch.
  """
  use Server.MCP.Tool

  schema do
    field :thread_id, :integer,
      description: "The workline you lead, when your session is bound to another thread (e.g. the lobby)"
  end

  @impl true
  def execute(params, frame) do
    case acting_thread(params, frame) do
      %Server.Thread{} = thread ->
        case Server.bring_branch_to_main(thread) do
          {:refused, why} -> fail(frame, why)
          {:error, why} -> fail(frame, inspect(why))
          result -> ok(frame, %{"result" => format(result)})
        end

      {:error, why} ->
        fail(frame, to_string(why))
    end
  end

  defp format({:rebased, n}), do: "rebased:#{n}"
  defp format(result), do: Atom.to_string(result)
end
