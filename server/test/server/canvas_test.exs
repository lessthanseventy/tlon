defmodule Server.CanvasTest do
  # The contribution graph as a 52 × 7 canvas: weeks are columns (Sunday on top), the last column is
  # this week. A picture is seven lines of `.` (blank) and `1`–`4` / `#` (shade); Life steps it on a torus.
  use ExUnit.Case, async: true

  alias Server.Canvas

  @today ~D[2026-10-08]

  test "the grid ends on this week's column, Sunday on top" do
    assert Canvas.date_at(51, 0, @today) == ~D[2026-10-04]
    assert Canvas.date_at(51, 4, @today) == @today
    assert Canvas.date_at(0, 0, @today) == ~D[2025-10-12]
    assert Date.day_of_week(Canvas.date_at(10, 0, @today), :sunday) == 1
  end

  test "a picture is seven rows of shades; anything else isn't a picture" do
    rows =
      ["#." <> String.duplicate(".", 50) | List.duplicate(String.duplicate(".", 52), 5)] ++
        ["1234" <> String.duplicate(".", 48)]

    assert {:ok, grid} = Canvas.parse(Enum.join(rows, "\n"))
    assert Canvas.shade(grid, 0, 0) == 4 and Canvas.shade(grid, 1, 0) == 0
    assert Enum.map(0..3, &Canvas.shade(grid, &1, 6)) == [1, 2, 3, 4]

    assert :error = Canvas.parse("too\nshort")
    assert :error = Canvas.parse(Enum.join(List.duplicate("xyz", 7), "\n"))
  end

  test "a picture is found in a fenced block inside a chatty message" do
    body =
      "today's canvas, a wave:\n```\n" <>
        Enum.join(List.duplicate(String.duplicate("#.", 26), 7), "\n") <> "\n```\nenjoy"

    assert {:ok, _} = Canvas.find_picture(body)
    assert :error = Canvas.find_picture("no picture here")
  end

  test "Life steps a blinker on the torus" do
    blank = List.duplicate(String.duplicate(".", 52), 7)

    vertical =
      blank
      |> List.replace_at(2, put(blank, 2, 10))
      |> List.replace_at(3, put(blank, 3, 10))
      |> List.replace_at(4, put(blank, 4, 10))

    {:ok, grid} = Canvas.parse(Enum.join(vertical, "\n"))
    stepped = Canvas.life(grid)
    assert for(c <- 9..11, do: Canvas.shade(stepped, c, 3) > 0) == [true, true, true]
    assert Canvas.shade(stepped, 10, 2) == 0 and Canvas.shade(stepped, 10, 4) == 0
    assert stepped |> Canvas.life() |> Canvas.shade(10, 2) > 0
  end

  test "the plan: shaded days before tomorrow, more commits for a darker shade; the future is skipped" do
    rows = List.duplicate(String.duplicate("#", 52), 7)
    {:ok, grid} = Canvas.parse(Enum.join(rows, "\n"))
    plan = Canvas.plan(grid, @today)
    assert Map.fetch!(plan, @today) == Canvas.commits_for(4)
    refute Map.has_key?(plan, Date.add(@today, 1))
    assert Canvas.commits_for(1) < Canvas.commits_for(4)
  end

  defp put(blank, row, col),
    do: blank |> Enum.at(row) |> String.to_charlist() |> List.replace_at(col, ?#) |> to_string()
end
