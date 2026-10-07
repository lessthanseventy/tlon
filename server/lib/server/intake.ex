defmodule Server.Intake do
  @moduledoc """
  What keeps the backlog moving with nobody at the keyboard. While a workspace has fewer worklines
  in flight than the cap (`"max_worklines"` in the settings file, default 4), its most urgent
  backlog ticket that nothing blocks (`Server.Tickets.blocked_in_workspace/1`) goes to the manager
  (`Server.Tickets.route/1`), who decides workline or thread and staffs it. One ticket per workspace
  per pass, so a full backlog arrives steadily, not in a flood; a routed ticket (`todo`) counts as
  in flight until its work starts. A workline waiting on the operator holds no slot — work goes on
  while gates queue for them — but open worklines in all stop at `"max_open_worklines"` (default 10),
  so a long night leaves a reviewable pile, not an endless one. Run by `Server.Jobs.Intake` on the cron.
  """
  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Ticket

  @cap 4
  @max_open 10
  @urgency %{"high" => 0, "med" => 1, "low" => 2}

  @doc "One pass over every workspace with a backlog. `cap` and `route` override for a test."
  def run(opts \\ []) do
    settings = Server.OperatorConfig.read()
    cap = opts[:cap] || settings["max_worklines"] || @cap
    max_open = opts[:max_open] || settings["max_open_worklines"] || @max_open
    route = opts[:route] || (&Server.Tickets.route/1)

    for ws <- Repo.all(from t in Ticket, where: t.status == "backlog", distinct: true, select: t.workspace_id),
        {working, open} = in_flight(ws),
        working < cap and open < max_open,
        ticket = next(ws),
        do: route.(ticket)

    :ok
  end

  # {being worked, open in all}: a workline waiting on the operator is open but not being worked
  defp in_flight(ws) do
    open =
      from(t in Thread,
        where: t.workspace_id == ^ws and t.state == "open" and not is_nil(t.stage) and t.stage != "merged"
      )

    all = Repo.aggregate(open, :count)
    waiting = Repo.aggregate(from(t in open, where: not is_nil(t.awaiting)), :count)
    routed = Repo.aggregate(from(t in Ticket, where: t.workspace_id == ^ws and t.status == "todo"), :count)
    {all - waiting + routed, all + routed}
  end

  defp next(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)

    from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog")
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(blocked, &1.id))
    |> Enum.min_by(&{Map.get(@urgency, &1.priority, 1), &1.sort || 0, &1.id}, fn -> nil end)
  end
end
