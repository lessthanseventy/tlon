defmodule Console.Panel.Terminal do
  @moduledoc """
  The center column: a REAL embedded terminal (design §4). Renders an `Console.Terminal`'s
  `render_state` — Ghostty's live cell grid — as truecolor runs, each cell carrying its own RGB
  from the VT engine (not a semantic palette). The cursor cell is inverted so you can see where
  you type, and the `inverse` attribute (SGR 7) swaps fg/bg like a real terminal.

  Renders edge-to-edge — no header row.

  Data is a `render_state` map (`%{cells, cursor, foreground, background}`) or `:no_session`.
  Pure: a render_state in → styled rows out, no TTY. The cockpit blits these through `Console.Board`,
  which already paints 24-bit colour.
  """
  @behaviour Console.Panel

  import Bitwise
  import Console.Panel, only: [line: 2]

  # Fallback colours when the emulator reports nil (use the terminal-native pair).
  @default_fg 0xC5C8C6
  @default_bg 0x000000
  @inverse_bit 32

  # Claude Code paints its theme `background` token — a pale cyan, observed as rgb(155,208,204) — as
  # the EXPLICIT per-cell bg on queued/injected message rows (your own input, cross-thread server
  # messages). The VT stores it faithfully, so without neutralising it those rows blit as cyan under
  # a phosphor theme. Remap the sentinel to the panel's own default so they read like the rest of the
  # screen. It's not a real background choice any harness means to show — matching the value is the
  # only signal console gets. (Value captured live via the probe below, 2026-08-21; earlier guesses of
  # 0x00CCCC/0x009999 never fired.)
  @bg_sentinels [0x9BD0CC]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(:no_session, rect) do
    Console.Panel.clip([line("no live session — Enter to spawn one here", :dim)], rect)
  end

  def render(%{cells: cells} = render_state, rect) do
    default_fg = rgb_int(render_state[:foreground]) || @default_fg
    default_bg = rgb_int(render_state[:background]) || @default_bg
    cursor = render_state[:cursor] || %{visible: false}

    cells
    |> Enum.with_index()
    |> Enum.map(fn {row, y} -> cell_runs(row, y, cursor, default_fg, default_bg) end)
    |> Console.Panel.clip(rect)
  end

  # One run per cell — its own RGB. Board.row_cells emits a cell per grapheme, so per-cell runs are
  # exactly right for a terminal, where adjacent cells routinely differ in colour.
  defp cell_runs(row, y, cursor, default_fg, default_bg) do
    row
    |> Enum.with_index()
    |> Enum.map(fn {{grapheme, fg, bg, flags}, x} ->
      char = if grapheme in ["", nil], do: " ", else: grapheme
      fg = rgb_int(fg) || default_fg
      bg = neutralize_sentinel(rgb_int(bg) || default_bg, default_bg)

      # inverse video (SGR 7) swaps, and the cursor cell inverts on top of that.
      {fg, bg} = if band(flags, @inverse_bit) == 0, do: {fg, bg}, else: {bg, fg}
      {fg, bg} = if cursor_at?(cursor, x, y), do: {bg, fg}, else: {fg, bg}

      {char, {:rgb, fg, bg}}
    end)
  end

  # A cell bg equal to Claude Code's `background` sentinel (see @bg_sentinels) reads as the panel
  # default; every other colour passes through untouched.
  defp neutralize_sentinel(bg, default_bg) when bg in @bg_sentinels, do: default_bg
  defp neutralize_sentinel(bg, _default_bg), do: bg

  defp cursor_at?(%{visible: true, x: cx, y: cy}, x, y), do: cx == x and cy == y
  defp cursor_at?(_cursor, _x, _y), do: false

  defp rgb_int(nil), do: nil
  defp rgb_int({r, g, b}), do: r * 65_536 + g * 256 + b
end
