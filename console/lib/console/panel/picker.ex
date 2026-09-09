defmodule Console.Panel.Picker do
  @moduledoc """
  The switcher / command-palette overlay's body (UX slice 2). The `Console.Cockpit` places it over
  the centre inside a `Console.Panel.Border` carrying the title; this paints what is inside: the
  query line, a rule, then the filtered rows.

  A row is `tag · [keycap] · label · context` — the tag dim (`thread`, `channel`, `global`,
  `drawer`), the keycap lit where there is one (the palette), the label bright, and the context
  dim and truncated last. Context is the half a footer keycap can never carry: for the switcher
  it is where the thread LIVES (`ficciones · #general`), for the palette it is the sentence saying
  what the verb does, which was the whole ask.

  The cursor row renders inverse (the palette's "this is the live one"), matching the rail.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [pad: 3, line: 2]

  alias Console.Panel

  # The tag column is fixed so labels line up into a column the eye can run down; the widest tag
  # in play is "workspace" (9).
  @tag_w 10

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  def render(%{items: items} = data, rect) do
    cursor = data[:cursor] || 0
    body_h = max(rect.h - 2, 1)

    painted =
      items
      |> Enum.with_index()
      |> Enum.drop(offset(cursor, body_h))
      |> Enum.take(body_h)
      |> Enum.map(fn {item, i} -> row(item, i == cursor, rect.w) end)

    Panel.clip([query_row(data, rect.w), Panel.rule(rect.w) | rows(painted)], rect)
  end

  def render(_data, rect), do: Panel.clip([], rect)

  # An empty result set says so, rather than leaving the operator staring at a blank box wondering
  # whether the overlay is broken.
  defp rows([]), do: [line("nothing matches", :dim)]
  defp rows(rows), do: rows

  # The typed query, with a block cursor after it — the same `▎` the composer and status bar use.
  defp query_row(data, w), do: pad([{"▸ ", :accent}, {data[:query] || "", :normal}, {"▎", :accent}], w, :normal)

  defp row(item, selected?, w) do
    style = if selected?, do: :selected, else: :normal
    tag = if selected?, do: :selected, else: :meta
    key = if selected?, do: :selected, else: :header
    dim = if selected?, do: :selected, else: :dim

    lead = [{if(selected?, do: "▸ ", else: "  "), style}, {tag_text(item), tag}]
    keys = keys_runs(item, key)
    label = [{item[:label] || "", style}]

    head = lead ++ keys ++ label
    room = max(w - Panel.row_width(head) - 2, 0)

    pad(head ++ context_runs(item, dim, room), w, style)
  end

  defp tag_text(item), do: String.pad_trailing(String.slice(item[:tag] || "", 0, @tag_w - 1), @tag_w)

  # Only the palette has keycaps; the switcher's rows leave the column out entirely rather than
  # padding an empty one, so a thread title starts where the eye already is.
  defp keys_runs(%{keys: keys}, style) when is_binary(keys) and keys != "", do: [{String.pad_trailing(keys, 12), style}]

  defp keys_runs(_item, _style), do: []

  # The context is the first thing to give when the frame is narrow — the label is the answer, the
  # context only qualifies it.
  defp context_runs(_item, _style, room) when room <= 1, do: []

  defp context_runs(item, style, room) do
    case item[:context] do
      nil -> []
      "" -> []
      text -> [{"  " <> String.slice(text, 0, room - 2), style}]
    end
  end

  @impl Panel
  def pick(%{items: items} = data, rect, local_y) do
    # row 0 is the query, row 1 the rule — the list starts at 2
    index = offset(data[:cursor] || 0, max(rect.h - 2, 1)) + local_y - 2

    case index >= 0 && Enum.at(items, index) do
      %{} = item -> {:picker_pick, item}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  @impl Panel
  def hints(_data), do: [{"↑↓", "move"}, {"⏎", "pick"}, {"esc", "close"}]

  # More rows than fit: scroll so the cursor is always the last visible row, never off the bottom.
  defp offset(cursor, body_h), do: max(cursor - body_h + 1, 0)

  @doc "The widest row the overlay would draw — the Cockpit sizes the box against it."
  @spec width(map()) :: non_neg_integer()
  def width(%{items: items}) do
    items
    |> Enum.map(fn item ->
      @tag_w + 2 + String.length(item[:label] || "") + String.length(item[:context] || "") +
        if(is_binary(item[:keys]), do: 12, else: 0)
    end)
    |> Enum.max(fn -> 0 end)
  end

  def width(_data), do: 0
end
