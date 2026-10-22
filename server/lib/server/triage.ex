defmodule Server.Triage do
  @moduledoc """
  The PM's triage: the backlog's changes, put in front of the workspace's PM (the `pm` seat on its
  bench) on a thread of its own, "the PM's triage", when one is due — a day after the last, or sooner
  once #{5} tickets have come in since. The brief is the server's reading, so the PM starts from it
  rather than from `list_tickets`: what is new, what sits under no epic, what nobody has touched in
  #{14} days, and pairs whose titles look alike (`Server.Recurrence`). The PM acts with the ticket
  tools: `update_ticket` (`parent_id` to file it under an epic, `because` to close a duplicate or a
  stale one, `priority`), `file_ticket` (`kind` epic or initiative). Run hourly (`Server.Jobs.Triage`).
  """
  import Ecto.Query

  alias Server.{Channel, Repo, Thread, Ticket, TicketLink}

  @title "the PM's triage"
  @every_s 20 * 3600
  @burst 5
  @stale_days 14
  @shown 15

  @doc "The triage thread's title."
  def title, do: @title

  @doc "Brief each workspace's PM whose triage is due; how many were briefed."
  def run(now \\ DateTime.utc_now()) do
    from(w in Server.Workspace, select: w.id)
    |> Repo.all()
    |> Enum.count(fn ws ->
      with %{} = pm <- ws |> Server.Workspaces.bench() |> Enum.find(&(&1.archetype == "pm")),
           {:ok, thread} <- thread(ws, pm) do
        brief(ws, pm, thread, now)
      else
        _ -> false
      end
    end)
  end

  defp brief(ws, pm, thread, now) do
    last = last_brief(thread)
    new = Repo.all(from t in tickets(ws), where: ^since(last), order_by: t.id)

    if is_nil(last) or DateTime.diff(now, last) >= @every_s or length(new) >= @burst do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "tlon", body: body(ws, pm.name, new, now)})
      true
    else
      false
    end
  end

  defp since(nil), do: dynamic(true)
  defp since(last), do: dynamic([t], t.created_at >= ^last)

  defp tickets(ws), do: from(t in Ticket, where: t.workspace_id == ^ws and t.kind == "ticket" and t.status != "done")

  defp body(ws, pm, new, now) do
    open = Repo.all(from t in tickets(ws), order_by: t.id)
    parented = MapSet.new(Repo.all(from l in TicketLink, where: l.kind == "parent", select: l.to_id))
    loose = Enum.reject(open, &MapSet.member?(parented, &1.id))
    stale_at = DateTime.add(now, -@stale_days, :day)
    stale = Enum.filter(open, &(&1.status in ~w(backlog todo) and DateTime.compare(&1.updated_at, stale_at) == :lt))

    [
      "@#{pm} 🗂 triage: #{length(open)} open tickets, #{length(new)} new since the last.",
      section("New", new),
      section("Loose (under no epic)", loose),
      section("Stale (untouched #{@stale_days}+ days)", stale),
      pairs(ws, open)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp section(_name, []), do: nil

  defp section(name, tickets) do
    more = if length(tickets) > @shown, do: "\n… and #{length(tickets) - @shown} more", else: ""

    "#{name}, #{length(tickets)}:\n" <>
      Enum.map_join(Enum.take(tickets, @shown), "\n", &"##{&1.id} #{&1.title}") <> more
  end

  defp pairs(ws, open) do
    ids = MapSet.new(open, & &1.id)

    found =
      for t <- open,
          o <- Server.Recurrence.similar_tickets(ws, t.title),
          o.id > t.id and MapSet.member?(ids, o.id),
          do: "##{t.id} / ##{o.id}: #{t.title}"

    if found != [], do: "Look alike, #{length(found)}:\n" <> Enum.join(Enum.take(found, 10), "\n")
  end

  defp last_brief(thread) do
    Repo.one(
      from m in Server.Message,
        where: m.thread_id == ^thread.id and like(m.body, "%🗂 triage%"),
        select: max(m.created_at)
    )
  end

  defp thread(ws, pm) do
    case Repo.one(
           from t in Thread,
             where: t.workspace_id == ^ws and t.title == @title and t.state == "open",
             order_by: [desc: t.id],
             limit: 1
         ) do
      %Thread{} = t ->
        {:ok, t}

      nil ->
        with {:ok, t} <- Channel.open_thread(%{title: @title, workspace_id: ws, scope: "machine"}),
             {:ok, _} <- Channel.assign_lead(t.id, pm.name) do
          {:ok, t}
        end
    end
  end
end
