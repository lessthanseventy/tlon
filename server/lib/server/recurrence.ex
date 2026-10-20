defmodule Server.Recurrence do
  @moduledoc """
  A fault seen again is one item seen twice, not two items. Filing a ticket or raising an issue first
  looks for open items, and ones closed in the last 30 days, that share its words (`similar_tickets/2`,
  `similar_issues/1`); a caller shown a match records the recurrence on it (`ticket_seen/3`,
  `issue_seen/3`) instead of filing another. A recurrence bumps `seen`, appends what was seen, reopens
  a closed item, and at #{3} sightings raises a ticket to high priority, so what keeps biting rises
  in the ranking intake already uses.

  The match is shared words weighted by how rare each is among the candidates (a word in one item
  counts far more than one in thirty), so a long summary matches on its distinctive words and two
  that share only "session" and "test" do not. It surfaces candidates and the caller decides: a false
  match costs one more call with `distinct: true`.
  """
  import Ecto.Query

  alias Server.Issue
  alias Server.Repo
  alias Server.Ticket

  @window_days 30
  @high_at 3
  @stop ~w(with that this from when have does into after before still never every only should would
           their them then than what which while there been were also because about again)

  # a candidate matches when its shared words weigh @enough: two rare words, or four or so common ones
  @enough 6.0

  # the prior keeps a small corpus from calling every word rare
  @prior 20

  @doc "Open tickets of `workspace_id`, and ones closed within the window, that look like `title`: best first, at most 3."
  def similar_tickets(workspace_id, title) do
    since = DateTime.add(DateTime.utc_now(), -@window_days, :day)

    from(t in Ticket,
      where: t.workspace_id == ^workspace_id and t.kind == "ticket",
      where: t.status != "done" or t.closed_at > ^since
    )
    |> Repo.all()
    |> best(title, & &1.title)
  end

  @doc "Open issues, and ones closed within the window, that look like `summary`: best first, at most 3."
  def similar_issues(summary) do
    since = DateTime.add(DateTime.utc_now(), -@window_days, :day)

    from(i in Issue, where: i.state == "open" or i.created_at > ^since)
    |> Repo.all()
    |> best(summary, &headline(&1.summary))
  end

  @doc "Record `detail`, seen by `by`, on ticket `id`: reopened if closed, high once seen #{3} times."
  def ticket_seen(id, detail, by) do
    case Repo.get(Ticket, id) do
      %Ticket{kind: "ticket"} = t ->
        seen = t.seen + 1

        Server.Tickets.update(t, %{
          seen: seen,
          status: if(t.status == "done", do: "backlog", else: t.status),
          priority: if(seen >= @high_at, do: "high", else: t.priority),
          body: (t.body || "") <> "\n\nSeen again (#{Date.utc_today()}, by #{by}): " <> String.trim(detail || "")
        })

      _ ->
        {:error, "no ticket ##{id}"}
    end
  end

  @doc "Record `detail`, seen by `by`, on issue `id`: reopened if closed, and the ticket that owns it seen again too."
  def issue_seen(id, detail, by) do
    case Repo.get(Issue, id) do
      %Issue{} = i ->
        line = "Seen again (#{Date.utc_today()}, by #{by}): " <> String.trim(detail || "")
        evidence = Enum.join(Enum.reject([i.evidence, line], &(&1 in [nil, ""])), "\n\n")

        with {:ok, issue} <-
               i |> Ecto.Changeset.change(seen: i.seen + 1, state: "open", evidence: evidence) |> Repo.update() do
          if i.ticket_id, do: ticket_seen(i.ticket_id, detail, by)
          {:ok, issue}
        end

      nil ->
        {:error, "no issue ##{id}"}
    end
  end

  @doc "The candidates as lines a caller can read: `#id (status) title`."
  def listing(items), do: Enum.map_join(items, "\n", &line/1)

  defp line(%Ticket{} = t), do: "ticket ##{t.id} (#{t.status}, seen #{t.seen}) #{t.title}"
  defp line(%Issue{} = i), do: "issue ##{i.id} (#{i.state}, seen #{i.seen}) #{headline(i.summary)}"

  defp best(items, text, key) do
    query = words(text)
    docs = Enum.map(items, &{&1, words(key.(&1))})
    df = docs |> Enum.flat_map(fn {_, ws} -> MapSet.to_list(ws) end) |> Enum.frequencies()
    weight = fn w -> :math.log((length(docs) + @prior) / (Map.get(df, w, 0) + 0.5)) end

    docs
    |> Enum.map(fn {item, ws} -> {query |> MapSet.intersection(ws) |> Enum.map(weight) |> Enum.sum(), item} end)
    |> Enum.filter(fn {s, _} -> s >= @enough end)
    |> Enum.sort_by(fn {s, _} -> -s end)
    |> Enum.take(3)
    |> Enum.map(&elem(&1, 1))
  end

  defp words(text) do
    (text || "")
    |> String.downcase()
    |> String.split(~r/[^a-z0-9_\-\.\/]+/, trim: true)
    |> Enum.map(&String.trim(&1, ".-/"))
    |> Enum.filter(&(String.length(&1) >= 4 and &1 not in @stop))
    |> MapSet.new()
  end

  defp headline(summary), do: summary |> to_string() |> String.slice(0, 200)
end
