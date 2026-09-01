defmodule Console.Panel.TicketBoardTest do
  # The Tickets kanban (Slice D3): side-by-side status columns of gutter-cards, with a cursor. Pure render.
  use ExUnit.Case, async: true

  alias Console.Panel.TicketBoard

  defp rect, do: %{x: 0, y: 0, w: 120, h: 40}
  defp text(rows), do: Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

  test "an empty board nudges you to file one" do
    assert TicketBoard.render(%{tickets: []}, rect()) |> text() =~ "no tickets"
  end

  test "the four status columns render side by side on the header row, with counts" do
    tickets = [
      %{id: 1, title: "auth", status: "backlog", priority: "high", assignee: nil},
      %{id: 2, title: "flaky", status: "backlog", priority: "med", assignee: "hr"},
      %{id: 3, title: "shipping", status: "doing", priority: "low", assignee: nil}
    ]

    rows = TicketBoard.render(%{tickets: tickets}, rect())
    header = rows |> List.first() |> Enum.map_join(fn {t, _} -> t end)

    # all four buckets sit on ONE row (kanban columns), not stacked
    assert header =~ "BACKLOG (2)"
    assert header =~ "TODO (0)"
    assert header =~ "DOING (1)"
    assert header =~ "DONE (0)"

    out = text(rows)
    assert out =~ "#1 auth"
    assert out =~ "↑"
    assert out =~ "#3 shipping"
  end

  test "the cursor {col,row} washes the selected ticket :selected" do
    tickets = [
      %{id: 1, title: "first", status: "backlog", priority: "med", assignee: nil},
      %{id: 2, title: "second", status: "backlog", priority: "med", assignee: nil}
    ]

    rows = TicketBoard.render(%{tickets: tickets, cursor: {0, 1}}, rect())
    # the second backlog card's title run is :selected; the first is not
    second = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "#2 second" end))
    assert Enum.any?(second, fn {t, s} -> t =~ "#2 second" and s == :selected end)
    first = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "#1 first" end))
    refute Enum.any?(first, fn {t, s} -> t =~ "#1 first" and s == :selected end)
  end

  test "empty columns render a placeholder, not nothing" do
    out = TicketBoard.render(%{tickets: [%{id: 1, title: "x", status: "todo", priority: "med", assignee: nil}]}, rect()) |> text()
    assert out =~ "BACKLOG (0)"
    assert out =~ "—"
  end

  test "by_column groups tickets in column order for the cursor to index" do
    tickets = [%{id: 1, status: "doing"}, %{id: 2, status: "backlog"}]
    assert [[%{id: 2}], [], [%{id: 1}], []] = TicketBoard.by_column(tickets)
  end
end
