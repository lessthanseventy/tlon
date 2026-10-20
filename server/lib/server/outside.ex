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

  @doc "Whether a thread, by its title and the name of its lead, is a citizen's study."
  def study?(title, lead, citizens \\ names()), do: title == @study and lead in citizens

  @doc """
  Register each citizen with a window (`Server.Profiles.citizen_names/0`: uqbar, the aleph) that has
  no agent yet, as `outside`, so a fresh or reset store grows them at boot rather than by hand. `:ok`.
  """
  def ensure_citizens(names \\ Server.Profiles.citizen_names()) do
    for name <- names,
        is_nil(Server.Staff.agent_by_name(name)),
        do: Server.Staff.register_agent(%{name: name, mandate: "outside", engine: "claude-code"})

    :ok
  end

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
  Uqbar's study on `workspace_id`: the thread it leads there, opened the first time and reopened if
  closed, as a standing schedule's thread is (its check-in posts there), so there is one study with
  one history. A post there wakes it, spawning its pane. `{:ok, thread}` or
  `{:error, :no_such_citizen | changeset}`.
  """
  def study(workspace_id) do
    with %Server.Agent{id: id} <- Server.Staff.agent_by_name("uqbar") || {:error, :no_such_citizen} do
      case Repo.one(
             from t in Server.Thread,
               where: t.workspace_id == ^workspace_id and t.agent_id == ^id and t.title == @study,
               order_by: [desc: t.id],
               limit: 1
           ) do
        nil -> Channel.open_thread(%{title: @study, workspace_id: workspace_id, scope: "machine", agent_id: id})
        %Server.Thread{} = t -> reopened(t)
      end
    end
  end

  defp reopened(%Server.Thread{id: id} = t) do
    case Channel.reopen_if_closed(id) do
      {:reopened, open} -> {:ok, open}
      :open -> {:ok, t}
      :no_thread -> {:error, :no_thread}
      {:error, _} = error -> error
    end
  end

  @checkin "uqbar's check-in"
  @checkin_body """
  Your check-in. Releases, the inbox, health, fixes: THE CHECK-IN in your role. Then post one line \
  here saying what you did, or that nothing needed you.\
  """

  @doc """
  Uqbar's standing check-in on `workspace_id`: an agent schedule every 50 minutes whose firing posts
  on its study, inside the warmth window, so its pane stays warm between them and runs the delegate
  loop. Created once; found as it is after (the operator may have retimed or disabled it).
  `{:ok, schedule}` or `{:error, :no_such_citizen | changeset}`.
  """
  def ensure_checkin(workspace_id) do
    with {:ok, study} <- study(workspace_id) do
      case Enum.find(Server.Schedules.in_workspace(workspace_id), &(&1.title == @checkin)) do
        %Server.Schedule{} = s -> {:ok, s}
        nil -> create_checkin(workspace_id, study)
      end
    end
  end

  defp create_checkin(workspace_id, study) do
    attrs = %{workspace_id: workspace_id, kind: "agent", agent: "uqbar", standing: true, title: @checkin}

    with {:ok, s} <- Server.Schedules.create(Map.merge(attrs, %{cron: "@every 50m", body: @checkin_body})),
         do: s |> Ecto.Changeset.change(thread_id: study.id) |> Repo.update()
  end
end
