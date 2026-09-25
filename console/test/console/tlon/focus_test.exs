defmodule Console.Tlon.FocusTest do
  @moduledoc """
  The Tlön lazygit focus state machine (design: docs/plans/2026-08-20-tlon-lazygit-panels-design.md):
  a pure reducer over (which column, which pane in it, which section, in the terminal?). Render and
  tmux wiring hang off it; this asserts the navigation contract headlessly.
  """
  use ExUnit.Case, async: true

  alias Console.Tlon.Focus

  # left column stacks Commits then Memory (3 sections); right column is Leaves (1 section).
  # `counts` is the item count per pane — what j/k clamps against.
  @layout %{
    left: [:commits, :memory],
    right: [:leaves],
    sections: %{commits: 1, memory: 3, leaves: 1},
    counts: %{commits: 5, memory: 8, leaves: 2}
  }

  defp nav, do: Focus.handle(Focus.new(), @layout, :toggle_terminal)

  describe "the terminal toggle" do
    test "starts in the terminal" do
      assert Focus.new().in_terminal?
    end

    test "Ctrl+Space toggles out to nav mode, landing on the first left pane" do
      s = nav()
      refute s.in_terminal?
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "Ctrl+Space toggles back into the terminal" do
      s = Focus.handle(nav(), @layout, :toggle_terminal)
      assert s.in_terminal?
    end

    test "nav intents are no-ops while in the terminal (keys belong to tmux)" do
      s = Focus.handle(Focus.new(), @layout, :pane_next)
      assert s == Focus.new()
    end
  end

  describe "h/l — panes up/down a column" do
    test "l moves to the next pane, clamping at the bottom" do
      s = Focus.handle(nav(), @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
      s = Focus.handle(s, @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
    end

    test "h moves to the previous pane, clamping at the top" do
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :pane_prev)
      assert Focus.focused_pane(s, @layout) == :commits
      s = Focus.handle(s, @layout, :pane_prev)
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "moving pane resets the section" do
      # onto memory, advance a section, then move off — the section clears
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 1
      assert Focus.handle(s, @layout, :pane_prev).section == 0
    end
  end

  describe "H/L — between columns" do
    test "L jumps to the right column's first pane" do
      s = Focus.handle(nav(), @layout, :col_right)
      assert Focus.focused_pane(s, @layout) == :leaves
    end

    test "H jumps back to the left column, clamping the pane index" do
      s =
        nav()
        |> Focus.handle(@layout, :pane_next)
        |> Focus.handle(@layout, :col_right)
        |> Focus.handle(@layout, :col_left)

      # left has 2 panes; a right index of 0 clamps fine, lands on the first left pane
      assert Focus.focused_pane(s, @layout) == :commits
    end

    test "switching column resets the section" do
      s = nav() |> Focus.handle(@layout, :pane_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 1
      assert Focus.handle(s, @layout, :col_right).section == 0
    end
  end

  describe "Tab — sections within a pane" do
    test "cycles through a multi-section pane and wraps" do
      s = Focus.handle(nav(), @layout, :pane_next)
      assert Focus.focused_pane(s, @layout) == :memory
      s = Focus.handle(s, @layout, :section_next)
      assert s.section == 1
      s = s |> Focus.handle(@layout, :section_next) |> Focus.handle(@layout, :section_next)
      assert s.section == 0
    end

    test "a single-section pane stays put" do
      s = Focus.handle(nav(), @layout, :section_next)
      assert s.section == 0
    end

    test "changing section drops the item cursor to the top (each section is its own list)" do
      s =
        nav()
        |> Focus.handle(@layout, :pane_next)
        |> Focus.handle(@layout, :item_next)
        |> Focus.handle(@layout, :item_next)

      assert Focus.cursor(s, @layout) == 2
      s = Focus.handle(s, @layout, :section_next)
      assert Focus.cursor(s, @layout) == 0
    end
  end

  describe "j/k — the item cursor within a pane" do
    test "starts at 0 and item_next advances, clamping at count-1" do
      s = nav()
      assert Focus.cursor(s, @layout) == 0
      s = Enum.reduce(1..10, s, fn _, acc -> Focus.handle(acc, @layout, :item_next) end)
      # commits has 5 items → clamps at index 4
      assert Focus.cursor(s, @layout) == 4
    end

    test "item_prev retreats, clamping at 0" do
      s = nav() |> Focus.handle(@layout, :item_next) |> Focus.handle(@layout, :item_next)
      assert Focus.cursor(s, @layout) == 2

      s =
        s |> Focus.handle(@layout, :item_prev) |> Focus.handle(@layout, :item_prev) |> Focus.handle(@layout, :item_prev)

      assert Focus.cursor(s, @layout) == 0
    end

    test "each pane remembers its own cursor across pane moves" do
      s =
        nav()
        |> Focus.handle(@layout, :item_next)
        |> Focus.handle(@layout, :item_next)
        # → commits cursor 2, move to memory
        |> Focus.handle(@layout, :pane_next)

      assert Focus.focused_pane(s, @layout) == :memory
      assert Focus.cursor(s, @layout) == 0
      s = Focus.handle(s, @layout, :item_next)
      assert Focus.cursor(s, @layout) == 1
      # back to commits — its cursor is still 2
      s = Focus.handle(s, @layout, :pane_prev)
      assert Focus.cursor(s, @layout) == 2
    end

    test "cursor clamps down if the list shrank beneath it (e.g. a habit was approved)" do
      s = Enum.reduce(1..7, nav(), fn _, acc -> Focus.handle(acc, @layout, :item_next) end)
      s = Focus.handle(s, @layout, :pane_next)
      # memory has 8 items → cursor sat at, say, 0 here; put it near the end and shrink
      s = Enum.reduce(1..7, s, fn _, acc -> Focus.handle(acc, @layout, :item_next) end)
      assert Focus.cursor(s, @layout) == 7
      shrunk = %{@layout | counts: %{@layout.counts | memory: 3}}
      assert Focus.cursor(s, shrunk) == 2
    end

    test "item intents are no-ops in the terminal" do
      s = Focus.handle(Focus.new(), @layout, :item_next)
      assert s == Focus.new()
    end
  end

  describe "jump/3 (Alt+digit)" do
    # Numbering contract (design 2026-08-23): 0 = terminal; left column 1..n top-down; right
    # column continues. Must match Console.View's border digits — pinned by a view_test.
    defp jump_layout, do: %{left: [:spaces, :stack, :memory], right: [:health, :crew], sections: %{}, counts: %{}}

    test "0 enters the terminal from nav" do
      s = %Focus{in_terminal?: false, column: :left, pane: 2}
      assert Focus.jump(s, jump_layout(), 0).in_terminal? == true
    end

    test "a left digit lands on that pane, implicit nav, section reset" do
      s = %Focus{in_terminal?: true, section: 1}
      j = Focus.jump(s, jump_layout(), 2)

      assert %{in_terminal?: false, column: :left, pane: 1, section: 0} =
               Map.take(j, [:in_terminal?, :column, :pane, :section])
    end

    test "a right digit continues past the left column" do
      j = Focus.jump(%Focus{}, jump_layout(), 5)
      assert %{in_terminal?: false, column: :right, pane: 1} = Map.take(j, [:in_terminal?, :column, :pane])
    end

    test "a digit past the last pane is a no-op" do
      s = %Focus{}
      assert Focus.jump(s, jump_layout(), 9) == s
    end
  end

  describe "Enter/Esc — the MAIN detail" do
    test "open_detail flips detail? on; close_detail flips it off" do
      s = nav()
      refute s.detail?
      s = Focus.handle(s, @layout, :open_detail)
      assert s.detail?
      s = Focus.handle(s, @layout, :close_detail)
      refute s.detail?
    end

    test "detail follows the focused pane's live cursor (no frozen index)" do
      # detail? is a mode; the pane + cursor at render time are the content, so moving the cursor
      # while open re-resolves the detail. We assert the state the renderer reads.
      s = nav() |> Focus.handle(@layout, :open_detail) |> Focus.handle(@layout, :item_next)
      assert s.detail?
      assert Focus.cursor(s, @layout) == 1
    end

    test "opening detail is a no-op in the terminal" do
      s = Focus.handle(Focus.new(), @layout, :open_detail)
      refute s.detail?
    end
  end
end
