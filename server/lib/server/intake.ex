defmodule Server.Intake do
  @moduledoc """
  What keeps the backlog moving with nobody at the keyboard. While a workspace has fewer worklines
  in flight than the cap (`"max_worklines"` in the settings file, default 4), its most urgent
  backlog ticket that nothing blocks (`Server.Tickets.blocked_in_workspace/1`) goes to the manager
  (`Server.Tickets.route/1`), who decides workline or thread and staffs it. One ticket per workspace
  per pass, so a full backlog arrives steadily, not in a flood; a routed ticket (`todo`) counts as
  in flight until its work starts. Run by `Server.Jobs.Intake` on the cron.
  """
  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Ticket

  @cap 4
  @urgency %{"high" => 0, "med" => 1, "low" => 2}

  @doc "One pass over every workspace with a backlog. `cap` and `route` override for a test."
  def run(opts \\ []) do
    cap = opts[:cap] || Server.OperatorConfig.read()["max_worklines"] || @cap
    route = opts[:route] || (&Server.Tickets.route/1)

    for ws <- Repo.all(from t in Ticket, where: t.status == "backlog", distinct: true, select: t.workspace_id),
        in_flight(ws) < cap,
        ticket = next(ws),
        do: route.(ticket)

    :ok
  end

  defp in_flight(ws) do
    worklines =
      Repo.aggregate(
        from(t in Thread,
          where: t.workspace_id == ^ws and t.state == "open" and not is_nil(t.stage) and t.stage != "merged"
        ),
        :count
      )

    routed = Repo.aggregate(from(t in Ticket, where: t.workspace_id == ^ws and t.status == "todo"), :count)
    worklines + routed
  end

  defp next(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)

    from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog")
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(blocked, &1.id))
    |> Enum.min_by(&{Map.get(@urgency, &1.priority, 1), &1.sort || 0, &1.id}, fn -> nil end)
  end
end
