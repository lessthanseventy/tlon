defmodule Console.MouseTest do
  @moduledoc """
  The pure half of mouse routing (design §8): which panel a screen cell hits, how a scroll offset
  clamps, and the wheel button → direction/step mapping. No TTY, no funes — the Cockpit interprets
  these; the live paint is the eye test.
  """
  use ExUnit.Case, async: true

  alias Console.Mouse
  alias Console.Panel.Border
  alias Console.Panel.Rail
  alias Console.Panel.StatusBar
  alias Console.Panel.Terminal

  # Synthetic placements with known rects — hit_panel only cares about the rect + the module
  # (to skip chrome). This mirrors the shape View.compose produces without depending on it.
  defp placements do
    [
      {Border, nil, %{x: 0, y: 0, w: 30, h: 38}},
      {Rail, %{groups: []}, %{x: 2, y: 1, w: 26, h: 36}},
      {Border, nil, %{x: 31, y: 0, w: 58, h: 38}},
      {Terminal, :no_session, %{x: 33, y: 1, w: 54, h: 36}},
      {StatusBar, nil, %{x: 0, y: 38, w: 120, h: 2}}
    ]
  end

  describe "hit_panel/3" do
    test "a cell inside a content placement's rect hits that panel" do
      assert {Rail, _, _} = Mouse.hit_panel(placements(), 5, 5)
      assert {Terminal, _, _} = Mouse.hit_panel(placements(), 60, 10)
    end

    test "a cell on a border frame hits nothing — borders are chrome, not content" do
      assert Mouse.hit_panel(placements(), 0, 0) == nil
      assert Mouse.hit_panel(placements(), 31, 0) == nil
    end

    test "a cell on the status bar hits nothing — chrome, not a selectable panel" do
      assert Mouse.hit_panel(placements(), 60, 39) == nil
    end

    test "a cell outside every rect hits nothing" do
      assert Mouse.hit_panel(placements(), 200, 200) == nil
    end
  end

  describe "clamp_offset/3" do
    test "negative offsets clamp to 0 (can't scroll above the top)" do
      assert Mouse.clamp_offset(-5, 40, 10) == 0
    end

    test "offsets past the content clamp to max(0, content_height - h)" do
      # 40 rows of content in a 10-row window → the last valid top is row 30.
      assert Mouse.clamp_offset(50, 40, 10) == 30
      assert Mouse.clamp_offset(30, 40, 10) == 30
    end

    test "content shorter than the window clamps to 0 (nothing to scroll)" do
      assert Mouse.clamp_offset(5, 3, 10) == 0
    end
  end

  describe "to_cell/1 — SGR coordinates are 1-based, rects are 0-based" do
    test "translates the terminal's 1-based report to the placement grid" do
      # SGR top-left is 1;1 → cell {0,0}; without the shift every click lands one row below.
      assert Mouse.to_cell(1) == 0
      assert Mouse.to_cell(38) == 37
    end

    test "never goes negative on a malformed 0" do
      assert Mouse.to_cell(0) == 0
    end
  end

  describe "wheel_of/1" do
    test "wheel up → :up (into history), wheel down → :down (toward newer)" do
      assert {:up, n} = Mouse.wheel_of(:wheel_up)
      assert {:down, ^n} = Mouse.wheel_of(:wheel_down)
      assert n >= 1
    end
  end
end
