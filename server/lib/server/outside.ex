defmodule Server.Outside do
  @moduledoc """
  Citizens from outside the bench (Uqbar design, `docs/plans/2026-10-08-uqbar-design.md` §6): an
  agent registered on the server but seated on no workspace's bench, like `uqbar`, the operator's own
  Claude Code session. It posts signed as itself, never as the operator, and is never staffed, routed
  to or picked as a lead. The door refuses a seated coworker's name, so it can't speak for one.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo

  @doc "Post `body` to `thread_id` as outside citizen `name`. `{:ok, message}` | `{:error, :no_such_citizen | :seated | changeset}`."
  def post(thread_id, name, body) do
    case Server.Staff.agent_by_name(name) do
      nil ->
        {:error, :no_such_citizen}

      agent ->
        if Repo.exists?(from w in Server.WorkspaceAgent, where: w.agent_id == ^agent.id),
          do: {:error, :seated},
          else: Channel.post(%{thread_id: thread_id, author: name, body: body})
    end
  end
end
