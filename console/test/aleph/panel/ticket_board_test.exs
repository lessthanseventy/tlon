defmodule Console.Panel.TicketBoardTest do
  # The Tickets board (Slice 3.5): a status-grouped list of the workspace's tickets. Pure render.
  use ExUnit.Case, async: true

  alias Console.Panel.TicketBoard

  defp rect, do: %{x: 0, y: 0, w: 80, h: 40}
  defp text(rows), do: Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

  test "an empty board nudges you to file one" do
    assert TicketBoard.render(%{tickets: []}, rect()) |> text() =~ "no tickets"
  end

  test "tickets group under their status columns with counts" do
    tickets = [
      %{id: 1, title: "auth broken", status: "backlog", priority: "high", assignee: nil},
      %{id: 2, title: "flaky test", status: "backlog", priority: "med", assignee: "hronir"},
      %{id: 3, title: "shipping", status: "doing", priority: "low", assignee: nil}
    ]

    out = TicketBoard.render(%{tickets: tickets}, rect()) |> text()

    assert out =~ "BACKLOG (2)"
    assert out =~ "#1 auth broken"
    assert out =~ "↑"
    assert out =~ "@hronir"
    assert out =~ "DOING (1)"
    assert out =~ "#3 shipping"
    assert out =~ "TODO (0)"
    assert out =~ "DONE (0)"
  end

  test "empty columns render a placeholder, not nothing" do
    out = TicketBoard.render(%{tickets: [%{id: 1, title: "x", status: "todo", priority: "med", assignee: nil}]}, rect()) |> text()
    assert out =~ "BACKLOG (0)"
    assert out =~ "  —"
  end
end
