defmodule Server.Intake do
  @moduledoc """
  What keeps the backlog moving with nobody at the keyboard. While a workspace has fewer worklines
  in flight than the cap (`"max_worklines"` in the settings file, default 4), its most urgent
  backlog ticket that nothing blocks (`Server.Tickets.blocked_in_workspace/1`) goes to the manager
  (`Server.Tickets.route/1`), who decides workline or thread and staffs it. One ticket per workspace
  per pass, so a full backlog arrives steadily, not in a flood; a routed ticket (`todo`) counts as
  in flight until its work starts. A workline waiting on the operator holds no slot — work goes on
  while gates queue for them — but open worklines in all stop at `"max_open_worklines"` (default 10),
  so a long night leaves a reviewable pile, not an endless one. A routed ticket the manager hasn't
  started within `@stalled_after` is started by intake itself, with the workspace's lead
  (`Server.Tickets.start_thread/1`), and the sheriff told: a handed-over ticket never holds a slot
  in silence. A ticket the manager labelled `held` (it waits on something; the why in its body) is
  neither routed nor started until the label comes off. Run by `Server.Jobs.Intake` on the cron.
  """
  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Ticket

  @doc "One pass over every workspace with a backlog. `cap` and `route` override for a test."
  def run(opts \\ []) do
    cap = opts[:cap] || Server.OperatorConfig.setting("max_worklines")
    max_open = opts[:max_open] || Server.OperatorConfig.setting("max_open_worklines")
    route = opts[:route] || (&Server.Tickets.route/1)

    start_stalled(opts)

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

    # a `todo` ticket whose promoted thread closed holds no slot — nothing else would ever move it on
    routed =
      from(t in Ticket,
        where: t.workspace_id == ^ws and t.status == "todo",
        where:
          not exists(
            from tt in Server.TicketThread,
              join: th in Thread,
              on: th.id == tt.thread_id,
              where: tt.ticket_id == parent_as(:t).id and tt.kind == "promoted" and th.state == "closed"
          )
      )
      |> from(as: :t)
      |> Repo.aggregate(:count)

    {all - waiting + routed, all + routed}
  end

  # routed (`todo`) longer than `after_s` ago, with no thread it was started in
  defp stalled(after_s) do
    cutoff = DateTime.add(DateTime.utc_now(), -after_s, :second)

    from(t in Ticket,
      where: t.status == "todo" and t.updated_at < ^cutoff,
      where:
        not exists(from tt in Server.TicketThread, where: tt.ticket_id == parent_as(:t).id and tt.kind == "promoted")
    )
    |> from(as: :t)
    |> Repo.all()
  end

  defp start_stalled(opts) do
    after_s = opts[:stalled_after] || Server.OperatorConfig.setting("stalled_ticket_minutes") * 60
    for ticket <- stalled(after_s), not held?(ticket), do: start_stalled_ticket(ticket)
  end

  defp start_stalled_ticket(ticket) do
    with {:ok, thread} <- Server.Tickets.start_thread(ticket) do
      why =
        "ticket ##{ticket.id} was routed to the manager and not staffed in 30 minutes, so intake started it here with the lead"

      Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: "⏱ #{why}."})
      Server.Sheriff.report(thread, why)
    end
  end

  @doc """
  The ticket intake starts next in workspace `ws`: the most urgent backlog ticket nothing blocks, or
  nil. An epic is never routed; its children are, by the higher of their own and their epic's priority,
  the children of an epic already `doing` first, each epic's lowest-`sort` step before its later ones.
  Equally urgent loose tickets go in board order (`Server.Tickets.in_workspace/1`), the top first.
  """
  def next(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)
    epics = epics_of(ws)

    from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog" and t.kind == "ticket")
    |> Repo.all()
    |> Enum.reject(&(MapSet.member?(blocked, &1.id) or held?(&1)))
    |> first_step_of_each_epic(epics)
    |> Enum.min_by(&rank(&1, epics), fn -> nil end)
  end

  # %{child_id => epic}: which epic (if any) each ticket of the workspace belongs to
  defp epics_of(ws) do
    from(l in Server.TicketLink,
      join: e in Ticket,
      on: e.id == l.from_id,
      where: l.kind == "parent" and e.workspace_id == ^ws,
      select: {l.to_id, e}
    )
    |> Repo.all()
    |> Map.new()
  end

  # step order inside an epic: only its lowest-sort candidate may compete with the rest
  defp first_step_of_each_epic(tickets, epics) do
    {children, loose} = Enum.split_with(tickets, &Map.has_key?(epics, &1.id))

    firsts =
      children
      |> Enum.group_by(&epics[&1.id].id)
      |> Enum.map(fn {_epic, steps} -> Enum.min_by(steps, &{&1.sort || 0, &1.id}) end)

    loose ++ firsts
  end

  # effective priority = the higher of the ticket's and its epic's; a doing epic's child goes before the rest
  defp rank(ticket, epics) do
    epic = epics[ticket.id]
    urgency = Enum.min([Ticket.urgency(ticket) | List.wrap(epic && Ticket.urgency(epic))])
    {urgency, if(epic && epic.status == "doing", do: 0, else: 1), -(ticket.sort || 0), -ticket.id}
  end

  @doc "Whether a ticket is parked by the `held` label — intake never starts it."
  def held?(%Ticket{labels: labels}), do: is_list(labels) and "held" in labels
end
