defmodule Console.Panel.Border do
  @moduledoc """
  A rounded box that frames a section, with the section's identity ON the frame (design
  2026-08-23): `╭─ 2 STACK ───╮` — jump digit first, then the title, or a carousel tab strip
  (`5 CREW · ACTIVITY · LEAVES`, active tab lit), plus an optional right-aligned hint on the
  bottom rule. Rendered *under* the panel it wraps — `Console.View` places the border first and
  the content at an inset rect. `%{focused: true}` swaps to a heavy double rule in `:accent`
  (the lazygit active-pane cue, legible on shape alone).
  """
  @behaviour Console.Panel

  alias Console.Panel

  @thin {"╭", "╮", "╰", "╯", "─", "│"}
  @heavy {"╔", "╗", "╚", "╝", "═", "║"}

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(data, rect) when is_map(data) do
    focused? = data[:focused] == true
    frame = if focused?, do: :accent, else: :separator
    glyphs = if focused?, do: @heavy, else: @thin
    box(rect, frame, glyphs, label_runs(data, focused?), hint_runs(data))
  end

  def render(_data, rect), do: box(rect, :separator, @thin, [], [])

  @doc """
  Which carousel tab a click at top-row local `x` lands on (index into `data.tabs`), or nil.
  Mirrors the offsets `label_runs/2` draws (the WindowBar `tab_at_x` idiom) so the clickable
  regions can't drift from the paint; the border_test pins the agreement.
  """
  @spec tab_at_x(term(), non_neg_integer()) :: non_neg_integer() | nil
  def tab_at_x(%{tabs: tabs} = data, x) when is_list(tabs) and tabs != [] do
    # corner + 1 rule char + the leading space + the digit run ("5 ").
    first = 3 + digit_width(data)

    tabs
    |> Enum.with_index()
    |> Enum.reduce_while(first, fn {{label, _active?}, i}, s ->
      e = s + String.length(label)
      if x >= s and x < e, do: {:halt, {:hit, i}}, else: {:cont, e + 3}
    end)
    |> case do
      {:hit, i} -> i
      _ -> nil
    end
  end

  def tab_at_x(_data, _x), do: nil

  defp digit_width(%{digit: d}) when is_integer(d), do: String.length("#{d} ")
  defp digit_width(_data), do: 0

  # ` 2 STACK ` (digit first — the Alt+digit jump affordance) or the tab strip; [] → bare rule.
  defp label_runs(data, focused?) do
    title_style = if focused?, do: :accent, else: :header

    body =
      cond do
        is_list(data[:tabs]) and data[:tabs] != [] -> tab_runs(data[:tabs])
        is_binary(data[:title]) -> [{data[:title], title_style}]
        true -> []
      end

    digit = if is_integer(data[:digit]), do: [{"#{data[:digit]} ", :label}], else: []

    case digit ++ body do
      [] -> []
      runs -> [{" ", :normal} | runs] ++ [{" ", :normal}]
    end
  end

  defp tab_runs(tabs) do
    Enum.map_intersperse(tabs, {" · ", :dim}, fn {label, active?} -> {label, if(active?, do: :header, else: :dim)} end)
  end

  defp hint_runs(%{hint: hint}) when is_binary(hint), do: [{" ", :normal}, {hint, :dim}, {" ", :normal}]
  defp hint_runs(_data), do: []

  defp box(%{w: w, h: h} = rect, style, {tl, tr, bl, br, horiz, vert}, label, hint) when w >= 2 and h >= 2 do
    inner = w - 2
    top = frame_row(tl, tr, horiz, inner, style, label, 1)
    bottom = frame_row(bl, br, horiz, inner, style, hint, max(inner - Panel.row_width(hint) - 2, 0))
    side = [{vert, style}, {String.duplicate(" ", inner), :normal}, {vert, style}]

    Panel.clip([top] ++ List.duplicate(side, h - 2) ++ [bottom], rect)
  end

  defp box(_rect, _style, _glyphs, _label, _hint), do: []

  # A frame row: corners + rule, with `overlay` punched in at rule offset `at`. An overlay that
  # doesn't fit is dropped whole (clipping it would eat the corner).
  defp frame_row(left, right, horiz, inner, style, [], _at),
    do: [{left <> String.duplicate(horiz, inner) <> right, style}]

  defp frame_row(left, right, horiz, inner, style, overlay, at) do
    ow = Panel.row_width(overlay)

    if ow + at > inner do
      frame_row(left, right, horiz, inner, style, [], at)
    else
      [{left <> String.duplicate(horiz, at), style}] ++
        overlay ++ [{String.duplicate(horiz, inner - at - ow) <> right, style}]
    end
  end
end
