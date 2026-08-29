defmodule Console.Panel.Detail do
  @moduledoc """
  MAIN's detail view (design §interaction model): when the Tlön focus opens a selection with
  `Enter`, this replaces the center terminal — a commit's diff, a fact's full text — until `Esc`
  closes it (the tmux terminal keeps running underneath, unseen). Dumb by design: the cockpit's
  per-pane resolver produces `%{title, lines}` where `lines` are already `{text, style}` runs, so
  Detail owns no per-pane knowledge — it prints a title, a rule, then the lines, scrollable.

  `nil` data (detail mode with nothing resolved) renders a quiet placeholder rather than a blank.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0, rule: 1]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(nil, rect), do: Console.Panel.clip([line("no detail", :dim)], rect)

  def render(%{title: title} = data, rect) do
    lines = Map.get(data, :lines, [])
    scroll = Map.get(data, :scroll, 0)

    rows = [line(title, :header), rule(rect.w) | Enum.map(lines, &to_row/1)]
    Console.Panel.clip(Enum.drop(rows, scroll), rect)
  end

  # A resolver line is either a ready `{text, style}` run or a bare row (list of runs). Normalize
  # to a row so Detail stays agnostic about which the resolver produced.
  defp to_row({text, style}) when is_binary(text) and is_atom(style), do: [{text, style}]
  defp to_row(row) when is_list(row), do: row
  defp to_row(_), do: blank()
end
