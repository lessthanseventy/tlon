defmodule Console.Panel.TicketBoard do
  @moduledoc """
  The Tickets **kanban** (Slice D3, 2026-09-01): the workspace's lightweight tracker as side-by-side
  status columns (backlog · todo · doing · done), each a stack of gutter-cards. A `{col, row}` cursor
  (or nil) highlights the selected ticket; the cockpit drives it (h/l/j/k move · p advance · n file ·
  Esc close). Pure render: `%{tickets: [%{id, title, status, priority, assignee}], cursor: {c, r} | nil}`.
  """
  @behaviour Console.Panel

  alias Console.Card
  alias Console.Panel

  @columns ~w(backlog todo doing done)
  @status_color %{"backlog" => :st_idle, "todo" => :st_open, "doing" => :st_working, "done" => :st_done}

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def hints(_data), do: [{"h/l·j/k", "move"}, {"p", "advance"}, {"n", "new"}, {"⏎", "promote"}]

  @doc "Tickets grouped by status, in column order — the cockpit indexes its cursor into this."
  def by_column(tickets) do
    by = Enum.group_by(tickets, & &1.status)
    Enum.map(@columns, &Map.get(by, &1, []))
  end

  @impl Panel
  def render(%{tickets: []}, rect), do: Panel.clip([[{"no tickets — press n to file one", :dim}]], rect)

  def render(%{tickets: tickets} = data, rect) do
    cursor = data[:cursor]
    col_w = max(div(rect.w, length(@columns)), 8)
    columns = by_column(tickets)

    columns
    |> Enum.with_index()
    |> Enum.map(fn {ts, ci} -> column_rows(Enum.at(@columns, ci), ts, ci, cursor, col_w) end)
    |> zip_columns(col_w)
    |> Panel.clip(rect)
  end

  # One column's rows: a coloured header with the count, then a gutter-card per ticket (selected one
  # washed), or a dim placeholder. Not yet width-fitted — zip_columns pads each to col_w.
  defp column_rows(status, tickets, ci, cursor, _col_w) do
    header = [[{String.upcase(status), @status_color[status]}, {" (#{length(tickets)})", :dim}], []]

    cards =
      case tickets do
        [] -> [[{"  —", :dim}]]
        ts -> ts |> Enum.with_index() |> Enum.flat_map(fn {t, ri} -> ticket_card(t, {ci, ri} == cursor) end)
      end

    header ++ cards
  end

  defp ticket_card(t, selected?) do
    prio = priority_mark(t[:priority])
    who = if t[:assignee], do: " @#{t.assignee}", else: ""
    title_style = if selected?, do: :selected, else: :normal
    header = [{"#{prio} ", :accent}, {"##{t.id} #{t.title}", title_style}, {who, :dim}]
    Card.gutter_card(header, [], status_atom(t.status))
  end

  # Zip N columns into rows: pad each column's rows to col_w, pad short columns with blanks, then
  # concatenate the i-th row of every column so they render side by side.
  defp zip_columns(columns, col_w) do
    height = columns |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)

    padded =
      Enum.map(columns, fn col ->
        fitted = Enum.map(col, fn row -> Panel.pad(clip_row(row, col_w - 1), col_w, :normal) end)
        fitted ++ List.duplicate(Panel.pad([], col_w, :normal), height - length(fitted))
      end)

    for i <- 0..(max(height, 1) - 1) do
      Enum.flat_map(padded, &(Enum.at(&1, i) || []))
    end
  end

  defp clip_row(row, w), do: [row] |> Panel.clip(%{w: w, h: 1}) |> List.first() || []

  defp status_atom("backlog"), do: :idle
  defp status_atom("todo"), do: :open
  defp status_atom("doing"), do: :working
  defp status_atom("done"), do: :done
  defp status_atom(_), do: :open

  defp priority_mark("high"), do: "↑"
  defp priority_mark("low"), do: "↓"
  defp priority_mark(_med), do: "·"
end
