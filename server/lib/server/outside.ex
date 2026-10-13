defmodule Server.Outside do
  @moduledoc """
  Citizens from outside the bench (Uqbar design, `docs/plans/2026-10-08-uqbar-design.md` §6): an
  agent registered on the server but seated on no workspace's bench, like `uqbar`, the operator's
  delegate. It posts signed as itself, never as the operator, and is never routed to, staffed on
  another thread or picked as a lead by intake. It leads one thread of its own, its study
  (`study/1`), where the operator talks to it and its pane is spawned like a coworker's
  (`docs/plans/2026-10-13-cohesion-off-the-happy-path.md`, Cause 6). The door refuses a seated
  coworker's name, so it can't speak for one.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo

  @doc """
  Post `body` to `thread_id` as outside citizen `name`. `notice: true` posts it as a `notice`, an FYI
  the switchboard delivers to nobody, so it costs no coworker a turn. `{:ok, message}` |
  `{:error, :no_such_citizen | :seated | changeset}`.
  """
  def post(thread_id, name, body, opts \\ []) do
    kind = if opts[:notice], do: "notice", else: "chat"

    case Server.Staff.agent_by_name(name) do
      nil ->
        {:error, :no_such_citizen}

      agent ->
        if Repo.exists?(from w in Server.WorkspaceAgent, where: w.agent_id == ^agent.id),
          do: {:error, :seated},
          else: Channel.post(%{thread_id: thread_id, author: name, body: body, kind: kind})
    end
  end

  @study "Uqbar's study"

  @doc "The outside citizens' names: agents registered as `outside` and seated on no bench."
  def names do
    Repo.all(
      from a in Server.Agent,
        left_join: w in Server.WorkspaceAgent,
        on: w.agent_id == a.id,
        where: a.mandate == "outside" and is_nil(w.agent_id),
        order_by: a.name,
        select: a.name
    )
  end

  @doc """
  Uqbar's study on `workspace_id`: the open thread it leads there, opened when there is none (a closed
  one is history, so the next is fresh). A post there wakes it, spawning its pane. `{:ok, thread}` or
  `{:error, :no_such_citizen | changeset}`.
  """
  def study(workspace_id) do
    with %Server.Agent{id: id} <- Server.Staff.agent_by_name("uqbar") || {:error, :no_such_citizen} do
      case Repo.one(
             from t in Server.Thread,
               where: t.workspace_id == ^workspace_id and t.agent_id == ^id and t.title == @study and t.state == "open",
               order_by: [desc: t.id],
               limit: 1
           ) do
        %Server.Thread{} = t -> {:ok, t}
        nil -> Channel.open_thread(%{title: @study, workspace_id: workspace_id, scope: "machine", agent_id: id})
      end
    end
  end
end
