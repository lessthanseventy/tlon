defmodule Console.Panel.Composer do
  @moduledoc """
  The compose box — a growable multi-line input above the status bar (the `c` verb). Renders
  the FULL buffer wrapped to the width, with the `▎` cursor on its actual line/col: the marker
  is inserted into the text before wrapping, so it travels with the wrap instead of assuming
  the cursor sits on the current line. `Console.View` sizes the box to the wrapped line count
  (capped at half the frame); past the cap the window scrolls to keep the cursor visible.

  Data is `%{input: %{kind: :compose, buffer, cursor}}`.
  """
  @behaviour Console.Panel

  alias Console.Panel

  @marker "▎"
  # The "▸ " prompt gutter on the box's first row; continuation rows indent to align under it.
  @gutter 2

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(%{input: input}, rect) do
    rows =
      input
      |> lines(text_width(rect.w))
      |> window(rect.h)
      |> Enum.with_index()
      |> Enum.map(fn {ln, i} -> row(ln, i) end)

    Panel.clip(rows, rect)
  end

  @doc "The wrapped buffer (marker inserted at the cursor) — View sizes the box from its length."
  def lines(%{buffer: buffer} = input, width) do
    cursor = Map.get(input, :cursor, String.length(buffer))
    {before, aft} = buffer |> String.graphemes() |> Enum.split(cursor)
    marked = Enum.join(before) <> @marker <> Enum.join(aft)

    marked
    |> String.split("\n")
    |> Enum.flat_map(fn hard ->
      case Console.Text.wrap(hard, width) do
        [] -> [""]
        wrapped -> wrapped
      end
    end)
  end

  @doc "The wrap width inside a `w`-wide box (net of the prompt gutter)."
  def text_width(w), do: max(w - @gutter, 1)

  # Scroll so the cursor line stays visible: typing at the end pins it to the bottom row;
  # moving back up scrolls the window back.
  defp window(all, h) do
    marker_line = Enum.find_index(all, &String.contains?(&1, @marker)) || 0
    Enum.slice(all, window_start(length(all), marker_line, h), h)
  end

  defp window_start(count, _marker_line, h) when count <= h, do: 0
  defp window_start(count, marker_line, h), do: marker_line |> Kernel.-(h - 1) |> max(0) |> min(count - h)

  defp row(line, 0), do: [{"▸ ", :accent} | marker_runs(line)]
  defp row(line, _i), do: [{"  ", :normal} | marker_runs(line)]

  @doc "Style runs for a wrapped line — the `▎` marker accented, the text around it plain."
  def marker_runs(line) do
    case String.split(line, @marker, parts: 2) do
      [pre, post] -> [{pre, :normal}, {@marker, :accent}, {post, :normal}]
      [plain] -> [{plain, :normal}]
    end
  end
end
