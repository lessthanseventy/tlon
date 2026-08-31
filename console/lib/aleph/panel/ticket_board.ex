defmodule Console.Panel.TicketBoard do
  @moduledoc """
  The Tickets board (Slice 3.5, 2026-08-30): the workspace's lightweight tracker rendered as a
  status-grouped list (backlog → todo → doing → done) — a plain terminal board, no ceremony. Pure
  render: the cockpit hands it `%{tickets: [%{id, title, status, priority, assignee}]}` from
  `Server.Tickets.in_workspace/1`, so this stays testable without a live channel.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  @columns ~w(backlog todo doing done)

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{tickets: []}, rect), do: Console.Panel.clip([line("no tickets — file one with the tertius line", :dim)], rect)

  def render(%{tickets: tickets}, rect) do
    by_status = Enum.group_by(tickets, & &1.status)

    @columns
    |> Enum.flat_map(fn status -> column_rows(status, Map.get(by_status, status, [])) end)
    |> Console.Panel.clip(rect)
  end

  @impl Console.Panel
  def hints(_data), do: [{"⏎", "open"}, {"j/k", "move"}, {"p", "promote"}]

  # A status column: a header with its count, then its tickets (or a dim placeholder), then a gap.
  defp column_rows(status, tickets) do
    header = line("#{String.upcase(status)} (#{length(tickets)})", :header)

    body =
      case tickets do
        [] -> [line("  —", :dim)]
        ts -> Enum.map(ts, &ticket_row/1)
      end

    [header | body] ++ [blank()]
  end

  defp ticket_row(t) do
    prio = priority_mark(t[:priority])
    who = if t[:assignee], do: " @#{t.assignee}", else: ""
    [{"  #{prio} ", :accent}, {"##{t.id} #{t.title}", :normal}, {who, :dim}]
  end

  defp priority_mark("high"), do: "↑"
  defp priority_mark("low"), do: "↓"
  defp priority_mark(_med), do: "·"
end
