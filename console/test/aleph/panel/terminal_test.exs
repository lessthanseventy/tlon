defmodule Console.Panel.TerminalTest do
  @moduledoc """
  The center terminal is mostly cell-blitting (eye-tested live) — it renders edge-to-edge, no
  header row (the Tlön window strip moved out to `Console.Panel.WindowBar`; see its own test).
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Terminal

  @rect %{x: 0, y: 0, w: 40, h: 5}

  defp render_state(over \\ %{}) do
    Map.merge(%{cells: [[{"x", {200, 200, 200}, {0, 0, 0}, 0}]], cursor: %{visible: false}}, over)
  end

  test "renders cells edge-to-edge, no header row" do
    [first | _] = Terminal.render(render_state(), @rect)
    text = Enum.map_join(first, fn {t, _} -> t end)
    assert text =~ "x"
  end

  describe "Claude Code's cyan `background` sentinel is neutralized, never blitted" do
    # CC paints its theme `background` token — a pale cyan, observed live as rgb(155,208,204) — as
    # the explicit per-cell bg on queued/injected message rows. The VT stores it faithfully, so aleph
    # must remap it to the panel's own default (black) or those rows blit as cyan under a phosphor
    # theme. (Value captured 2026-08-21; earlier guesses of rgb(0,204,204)/rgb(0,153,153) never fired
    # and are NOT sentinels — the two below guard that they now pass through untouched.)
    test "the cyan sentinel rgb(155,208,204) is remapped to the terminal default (black)" do
      rs = render_state(%{cells: [[{"m", {51, 255, 0}, {155, 208, 204}, 0}]]})
      [first | _] = Terminal.render(rs, @rect)
      {char, {:rgb, fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
      assert {char, fg, bg} == {"m", 0x33FF00, 0x000000}
    end

    test "the earlier guessed values rgb(0,204,204)/rgb(0,153,153) are NOT sentinels — passed through" do
      for rgb <- [{0, 204, 204}, {0, 153, 153}] do
        rs = render_state(%{cells: [[{"m", {51, 255, 0}, rgb, 0}]]})
        [first | _] = Terminal.render(rs, @rect)
        {_, {:rgb, _fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
        {r, g, b} = rgb
        assert bg == r * 0x10000 + g * 0x100 + b
      end
    end

    test "a normal (non-sentinel) cell background is preserved untouched" do
      rs = render_state(%{cells: [[{"m", {51, 255, 0}, {16, 32, 24}, 0}]]})
      [first | _] = Terminal.render(rs, @rect)
      {_, {:rgb, _fg, bg}} = Enum.find(first, fn {t, _} -> t == "m" end)
      assert bg == 0x102018
    end
  end
end
