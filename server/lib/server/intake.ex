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
  (`Server.Tickets.start_thread/1`), and says so on its thread and the root: a handed-over ticket never holds a slot
  in silence — unless triage is in progress: the manager naming the ticket on the root thread, or a
  consult naming it, after the route, defers the stalled window (they run from the newest such message);
  the manager's open operator ask naming it blocks until answered, then defers the same way. Each deferral
  is noted once on the root thread, with a ⏱ line.
  A ticket the manager labelled `held` (it waits on something; the why in its body) is
  neither routed nor started until the label comes off, and holds no slot while routed. A `review`
  ticket opens a plain thread, not a workline: it holds no slot either, and one goes each pass ahead
  of the rank and at any cap, as the merge queue's input. Before routing, a backlog or routed ticket that a
  commit on origin's main names as a closing "(#N)" is closed, fixed by that sha: another workline did it.
  Run by `Server.Jobs.Intake` on the cron.
  """
  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Ticket

  # the office's own plumbing, by its labels: what the crew files about itself
  @self_repair ~w(tooling sandbox sheriff smoke wake staffing tests flake worklines landing merge-queue adapters release intake)

  @doc "One pass over every workspace with a backlog, none while the office is paused (`Server.Pause`). `cap` and `route` override for a test."
  def run(opts \\ []) do
    if Server.Pause.state() == :working, do: pass(opts), else: :ok
  end

  # {being worked, open in all}: a workline waiting on the operator is open but not being worked
  defp in_flight(ws) do
    open =
      from(t in Thread,
        where: t.workspace_id == ^ws and t.state == "open" and not is_nil(t.stage) and t.stage != "landed"
      )

    all = Repo.aggregate(open, :count)
    waiting = Repo.aggregate(from(t in open, where: not is_nil(t.awaiting)), :count)

    # a `todo` ticket whose promoted thread closed holds no slot — nothing else would ever move it on;
    # nor does a held one (it waits on something outside the office) or a review (it opens no workline)
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
      |> Repo.all()
      |> Enum.count(&(not held?(&1) and not Server.Tickets.review?(&1)))

    {all - waiting + routed, all + routed}
  end

  # routed (`todo`) longer than `after_s` ago, with no open thread it was started in: a closed one is a
  # workline abandoned back to the backlog and routed again
  defp stalled(after_s) do
    cutoff = DateTime.add(DateTime.utc_now(), -after_s, :second)

    from(t in Ticket,
      where: t.status == "todo" and t.updated_at < ^cutoff,
      where:
        not exists(
          from tt in Server.TicketThread,
            join: th in Thread,
            on: th.id == tt.thread_id,
            where: tt.ticket_id == parent_as(:t).id and tt.kind == "promoted" and th.state == "open"
        )
    )
    |> from(as: :t)
    |> Repo.all()
  end

  defp start_stalled(opts) do
    after_s = opts[:stalled_after] || Server.OperatorConfig.setting("stalled_ticket_minutes") * 60
    now = DateTime.utc_now()

    for ticket <- stalled(after_s), not held?(ticket) do
      case triage_message(ticket, after_s, now) do
        nil -> start_stalled_ticket(ticket)
        deferrer -> note_deferral(ticket, deferrer)
      end
    end
  end

  defp start_stalled_ticket(ticket) do
    with {:ok, thread} <- Server.Tickets.start_thread(ticket) do
      why =
        "ticket ##{ticket.id} was routed to the manager and not staffed in 30 minutes, so intake started it here with the lead"

      Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: "⏱ #{why}."})

      if root = Server.Channel.machine_thread(ticket.workspace_id) do
        Server.Channel.post(%{
          thread_id: root.id,
          author: "tlon",
          body: "⏱ ticket ##{ticket.id} was not staffed in 30 minutes: intake started it as thread ##{thread.id}."
        })
      end
    end
  end

  @doc """
  The ticket intake starts next in workspace `ws`: the most urgent backlog ticket nothing blocks, or
  nil. An epic is never routed; its children are, by the higher of their own and their epic's priority,
  the children of an epic already `doing` first, each epic's lowest-`sort` step before its later ones.
  Equally urgent loose tickets go in board order (`Server.Tickets.in_workspace/1`), the top first:
  filed first, taken first, unless someone moved one.

  Andrew's work first: below high priority, while the office's self-repair (`self_repair?/1`) holds at
  least as much of what is in flight (todo or doing) as his work does, his next ticket goes before it.
  Fixing its own plumbing files more plumbing, and without this the office works mostly on itself.
  """
  def next(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)
    epics = epics_of(ws)

    ready =
      from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog" and t.kind == "ticket")
      |> Repo.all()
      |> Enum.reject(&(MapSet.member?(blocked, &1.id) or held?(&1)))
      |> first_step_of_each_epic(epics)
      |> Enum.sort_by(&rank(&1, epics))

    with [best | _] <- ready,
         false <- elem(rank(best, epics), 0) == Ticket.urgency("high") or not self_repair?(best),
         true <- self_repair_ahead?(ws),
         %Ticket{} = mine <- Enum.find(ready, &(not self_repair?(&1))) do
      mine
    else
      _ -> List.first(ready)
    end
  end

  @doc "Whether a ticket is the office repairing itself, not Andrew's work: a label in #{inspect(@self_repair)}."
  def self_repair?(%Ticket{labels: labels}), do: is_list(labels) and Enum.any?(labels, &(&1 in @self_repair))

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
    {urgency, if(epic && epic.status == "doing", do: 0, else: 1), ticket.sort || 0, ticket.id}
  end

  @doc "Whether a ticket is parked by the `held` label — intake never starts it."
  def held?(%Ticket{labels: labels}), do: is_list(labels) and "held" in labels

  defp pass(opts) do
    cap = opts[:cap] || Server.OperatorConfig.setting("max_worklines")
    max_open = opts[:max_open] || Server.OperatorConfig.setting("max_open_worklines")
    route = opts[:route] || (&Server.Tickets.route/1)

    close_landed(opts)
    start_stalled(opts)

    for ws <- Repo.all(from t in Ticket, where: t.status == "backlog", distinct: true, select: t.workspace_id),
        ticket = next_review(ws) || under_cap(ws, cap, max_open),
        do: route.(ticket)

    :ok
  end

  @doc """
  `{sha, subject}` of the newest commits on origin's main, in the tlon checkout: what `run/1`'s `:landed`
  reads. A repo with no `origin/main` has none.
  """
  def landed_on_main do
    case Server.Git.cmd(Server.Profiles.tlon_root(), ["log", "origin/main", "-n", "300", "--format=%h %s"]) do
      {out, 0} -> out |> String.split("\n", trim: true) |> Enum.map(&List.to_tuple(String.split(&1, " ", parts: 2)))
      _ -> []
    end
  end

  # An open ticket a landed commit's subject ends with "(#N)" for is fixed: close it with that sha
  # (the newest naming it), so intake never routes work another workline already did. Only the closing
  # "(#N)" counts; a bare #N is as often a PR or thread number.
  defp close_landed(opts) do
    with landed when is_function(landed, 0) <- opts[:landed] do
      named =
        for {sha, subject} <- landed.(),
            [_, id] <- [Regex.run(~r/\(#(\d+)\)\s*$/, subject)],
            reduce: %{},
            do: (acc -> Map.put_new(acc, String.to_integer(id), sha))

      from(t in Ticket, where: t.id in ^Map.keys(named) and t.kind == "ticket" and t.status in ["backlog", "todo"])
      |> Repo.all()
      |> Enum.each(fn t ->
        sha = named[t.id]
        note = "Closed by intake: fixed by #{sha}, a commit on main that names it."
        {:ok, _} = Server.Tickets.update(t, %{status: "done", body: String.trim("#{t.body}\n\n#{note}")})
      end)
    end

    :ok
  end

  defp self_repair_ahead?(ws) do
    {self, mine} =
      from(t in Ticket, where: t.workspace_id == ^ws and t.kind == "ticket" and t.status in ["todo", "doing"])
      |> Repo.all()
      |> Enum.split_with(&self_repair?/1)

    length(self) >= length(mine)
  end

  # The message holding a stalled ticket in triage, or nil. Triage is a consult ask naming the ticket,
  # or the manager naming it on the workspace's root thread, after the route. A consult is never
  # resolved, so like a manager reply it only defers: `after_s` runs from the newest such message. The
  # manager's operator ask (a `prompt`) naming it holds the ticket while open, whatever its age.
  defp triage_message(ticket, after_s, now) do
    consults = naming(ticket, dynamic([m], not is_nil(m.consult_id) and m.mirrored == false))
    replies = manager_messages(ticket)

    case Enum.find(replies, &(&1.kind == "prompt" and is_nil(&1.resolved_at))) do
      nil -> recent_triage(consults ++ replies, after_s, now)
      open_ask -> open_ask
    end
  end

  defp recent_triage([], _after_s, _now), do: nil

  defp recent_triage(messages, after_s, now) do
    newest = Enum.max_by(messages, &touched/1, DateTime)
    if DateTime.diff(now, touched(newest)) < after_s, do: newest
  end

  defp touched(message), do: Enum.max(Enum.reject([message.created_at, message.resolved_at], &is_nil/1), DateTime)

  # One ⏱ line on the root thread per deferral: a line already newer than the deferring message says it.
  defp note_deferral(ticket, deferrer) do
    root = Server.Channel.machine_thread(ticket.workspace_id)

    if root && !noted_since?(ticket, root, deferrer) do
      Server.Channel.post(%{
        thread_id: root.id,
        author: "tlon",
        body: "⏱ ticket ##{ticket.id} is held in triage by #{deferrer.author}: #{wait(deferrer)}."
      })
    end
  end

  defp wait(%{kind: "prompt", resolved_at: nil}), do: "intake waits for the answer"

  defp wait(_deferrer),
    do: "intake waits until it has been quiet #{Server.OperatorConfig.setting("stalled_ticket_minutes")} minutes"

  defp noted_since?(ticket, root, deferrer) do
    from(m in Server.Message,
      where: m.thread_id == ^root.id and m.author == "tlon" and like(m.body, "⏱%"),
      where: m.created_at >= ^touched(deferrer)
    )
    |> Repo.all()
    |> Enum.any?(&Regex.match?(~r/##{ticket.id}(?!\d)/, &1.body))
  end

  defp manager_messages(ticket) do
    manager = Server.Workspaces.manager(ticket.workspace_id)
    root = Server.Channel.machine_thread(ticket.workspace_id)

    if manager && root do
      naming(ticket, dynamic([m], m.thread_id == ^root.id and m.author == ^manager.name))
    else
      []
    end
  end

  # Messages of the ticket's workspace, after the route, whose body names `#id`: not `#id0`, and not a
  # `thread #id` or `PR #id`, which name a thread or a PR that happens to share the number.
  defp naming(ticket, filter) do
    ref = ~r/(?<!thread )(?<!\bpr )##{ticket.id}(?!\d)/i

    from(m in Server.Message,
      join: th in Server.Thread,
      on: th.id == m.thread_id,
      where: th.workspace_id == ^ticket.workspace_id,
      where: ^dynamic([m], ^filter and m.created_at > ^ticket.updated_at and ilike(m.body, ^"%##{ticket.id}%"))
    )
    |> Repo.all()
    |> Enum.filter(&Regex.match?(ref, &1.body))
  end

  defp under_cap(ws, cap, max_open) do
    {working, open} = in_flight(ws)
    if working < cap and open < max_open, do: next(ws)
  end

  # a review is the merge queue's input and opens a plain thread, not a workline: it goes first, at any cap
  defp next_review(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)

    from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog" and t.kind == "ticket", order_by: t.id)
    |> Repo.all()
    |> Enum.find(&(Server.Tickets.review?(&1) and not held?(&1) and not MapSet.member?(blocked, &1.id)))
  end
end
