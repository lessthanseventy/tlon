defmodule Console.Cockpit.BoardsTest do
  @moduledoc """
  The Tickets kanban's pure math: cursor movement over the column grid, the status advance. The
  board KEYS moved to the drawer's own table with the boards (UX slice 1, task 4) — they're
  asserted in `Console.KeymapTest`'s "the drawer (Alt+d)" block now.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit.Boards

  # three columns: 2 / 0 / 3 tickets
  @cols [[:a, :b], [], [:c, :d, :e]]

  describe "move_grid/3 + clamp_grid/3" do
    test "h/l move columns, clamped at the edges" do
      assert Boards.move_grid({0, 0}, "h", @cols) == {0, 0}
      assert Boards.move_grid({0, 0}, "l", @cols) == {1, 0}
      assert Boards.move_grid({2, 1}, "l", @cols) == {2, 1}
    end

    test "j/k move rows, clamped to the column's length" do
      assert Boards.move_grid({2, 0}, "j", @cols) == {2, 1}
      assert Boards.move_grid({2, 2}, "j", @cols) == {2, 2}
      assert Boards.move_grid({2, 0}, "k", @cols) == {2, 0}
    end

    test "landing in a shorter column pulls the row back onto it (an empty column sits at row 0)" do
      assert Boards.move_grid({2, 2}, "h", @cols) == {1, 0}
      assert Boards.move_grid({0, 1}, "l", @cols) == {1, 0}
      assert Boards.clamp_grid(0, 9, @cols) == {0, 1}
    end
  end

  describe "next_status/1" do
    test "walks backlog → todo → doing → done and pins at done" do
      assert Boards.next_status("backlog") == "todo"
      assert Boards.next_status("doing") == "done"
      assert Boards.next_status("done") == "done"
    end

    test "an unknown status stays put" do
      assert Boards.next_status("weird") == "weird"
    end
  end
end
