defmodule Console.Transcript do
  @moduledoc """
  The Tlön machine-chat renderer — machine-scope threads (`Server.Channel.machine_threads/1`) as
  **foldable blocks**, each with its messages turn-grouped Slack-style. A pure
  `view_state → [row]` function in the `Console.Panel` row model (`{text, style}` runs), so it is
  headlessly testable and slots straight into the cockpit as a panel (the same renderer the Tlön
  `chat` tab drives via db-polling — the "one renderer, two surfaces" seam).

  `view_state` is
  `%{blocks: [%{thread: %{id, title}, messages: [%{author, body, created_at}]}], selected: idx,
  folded: MapSet(thread_id), zoom: thread_id | nil}`.

  - A **folded** thread renders as one `▸ title  (n)` row; an **expanded** one as `▾ title (n)`
    then its turn-grouped messages. The **selected** block's title carries `:selected`.
  - **zoom** collapses the surface to a single thread, expanded, full-pane.
  - Inside a block: consecutive messages from one author share a coloured `author  HH:MM` header;
    a change of author (or a >5-minute gap) opens a new turn; a day rollover drops a dated rule.

  Each author gets a stable truecolor (`{:rgb, fg, bg}` run style) so a speaker is scannable down
  the column — known coworkers hand-picked, any other voice hashed onto the palette.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Console.Panel

  # A spread of distinct truecolor foregrounds for unknown/hashed voices, plus hand-picked slots
  # for the known coworkers — carried in spirit from the Pass 1 stream palette.
  @palette [0x5FAFFF, 0xFFAF5F, 0x87FF87, 0xFF87D7, 0xD7AFFF, 0x5FD7D7, 0xFFD75F, 0xFF8787]
  # claude-machine kept alongside hronir-machine (its C2.3 rename) — old thread history still
  # colors correctly.
  # The operator is NOT here: `Server.Channel.operator?/1` routes them to `:operator` pink first.
  @known %{
    "tertius-machine" => 0xFF87D7,
    "hronir-machine" => 0x5FD7FF,
    "claude-machine" => 0x5FD7FF
  }

  @impl Panel
  def topics(_assigns), do: []

  @impl Panel
  # ZOOM: one thread, expanded, filling the pane. A zoomed thread that has since vanished (rotated
  # out from under the cursor) falls back to the list rather than a blank screen.
  def render(%{zoom: id} = data, rect) when not is_nil(id) do
    case Enum.find(data.blocks, &(&1.thread.id == id)) do
      nil ->
        render(%{data | zoom: nil}, rect)

      block ->
        header = [line("◄ #{title(block)}  ·  zoomed (esc)", :header), blank()]
        Panel.clip(header ++ message_rows(block.messages, rect.w), rect)
    end
  end

  # LIST: one foldable block per machine thread (no standing title — the tmux tab already says
  # `chat`, and a floating title reads oddly once the list bottom-anchors).
  def render(%{blocks: blocks} = data, rect) do
    body =
      case blocks do
        [] ->
          [line("no machine threads yet", :dim)]

        bs ->
          bs
          |> Enum.with_index()
          |> Enum.flat_map(fn {block, i} -> block_rows(block, i, data, rect.w) end)
      end

    Panel.clip(body, rect)
  end

  @doc """
  ONE thread's transcript rows (turn-grouped, day rules, hanging indent), no surrounding chrome —
  the machine-chat center conversation; the caller owns the header/composer around it.
  """
  @spec thread_rows(map(), pos_integer()) :: [[{String.t(), term()}]]
  def thread_rows(%{messages: messages}, w), do: message_rows(messages, w)

  @doc """
  The row index of the selected block's HEADER within `render/2`'s list output — what a viewport
  scrolls to so browsing keeps the selection on screen (the loop's reveal). Row counts only (the
  selected-style difference never changes a block's height), so it stays in lockstep with
  `render/2` by construction. nil when zoomed (single thread, no list) or empty.
  """
  @spec selected_row(map(), pos_integer()) :: non_neg_integer() | nil
  def selected_row(%{zoom: id}, _w) when not is_nil(id), do: nil
  def selected_row(%{blocks: []}, _w), do: nil

  def selected_row(%{blocks: blocks} = data, w) do
    blocks
    |> Enum.take(data.selected)
    |> Enum.with_index()
    |> Enum.reduce(0, fn {block, i}, acc -> acc + length(block_rows(block, i, data, w)) end)
  end

  # A thread block reads as one EPISODE: the `▸/▾ title` header carries its participants, message
  # count, and open/closed state (selected → highlighted, closed → dimmed), then its messages unless
  # folded, then a trailing blank so episodes read apart.
  defp block_rows(block, index, data, w) do
    folded? = MapSet.member?(data.folded, block.thread.id)
    closed? = block.thread.state == "closed"
    arrow = if folded?, do: "▸", else: "▾"

    title_style =
      cond do
        index == data.selected -> :selected
        closed? -> :dim
        true -> :header
      end

    head = [{"#{arrow} ", :accent}, {title(block), title_style}, {meta(block, closed?), :dim}]
    msgs = if folded?, do: [], else: message_rows(block.messages, w)

    [head | msgs] ++ [blank()]
  end

  # The dim `· pi·claude · (3) · closed` suffix on an episode header — who's in it, how many
  # messages, and whether it's resolved.
  defp meta(block, closed?) do
    who =
      case block.messages |> Enum.map(& &1.author) |> Enum.uniq() do
        [] -> ""
        authors -> "  " <> Enum.join(authors, "·")
      end

    who <> "  (#{length(block.messages)})" <> if(closed?, do: "  · closed", else: "")
  end

  defp title(%{thread: %{title: title}}), do: title || "untitled"

  # A thread's messages, turn-grouped: fold the (last author, last timestamp) cursor through them,
  # emitting day dividers, turn headers, and indented bodies.
  defp message_rows(messages, w) do
    {rows, _cursor} =
      Enum.reduce(messages, {[], %{author: nil, at: nil}}, fn message, {rows, cursor} ->
        {new_rows, cursor} = message_rows(message, cursor, w)
        {rows ++ new_rows, cursor}
      end)

    rows
  end

  defp message_rows(%{author: author, body: body, created_at: at}, cursor, w) do
    day? = day_divider?(cursor.at, at)
    turn? = day? or author != cursor.author or gap?(cursor.at, at)

    lead =
      cond do
        day? -> if(cursor.author, do: [blank()], else: []) ++ [day_divider(at, w), blank()]
        # One blank row between message blocks — turn changes AND same-turn follow-ups both breathe.
        cursor.author != nil -> [blank()]
        true -> []
      end

    head = if turn?, do: [header_row(author, at)], else: []
    {lead ++ head ++ body_rows(body, w, body_style(author)), %{author: author, at: at}}
  end

  # The operator's messages read pink whole (`:operator`); agents keep the green body.
  defp body_style(author), do: if(Server.Channel.operator?(author), do: :operator, else: :normal)

  # A turn header: the coloured author name, a gap, then a dim `HH:MM`.
  defp header_row(author, at), do: [{author, author_style(author)}, {"  ", :dim}, {time(at), :dim}]

  # The body wrapped to the column (paragraph breaks render as blank rows) with a hanging
  # two-space indent, so author names stay a scannable left edge.
  defp body_rows(body, w, style) do
    width = max(w - 2, 1)

    (body || "")
    |> Console.Text.wrap_paragraphs(width)
    |> Enum.map(&indent_row(&1, style))
  end

  defp indent_row("", _style), do: blank()
  defp indent_row(text, style), do: line("  " <> text, style)

  # A centred, dimmed date rule filling the column (`──── Fri, 15 Aug ────`).
  defp day_divider(%DateTime{} = at, w) do
    label = " " <> Calendar.strftime(at, "%a, %-d %b") <> " "
    pad = max(max(w, 20) - String.length(label), 2)
    left = div(pad, 2)
    [{String.duplicate("─", left) <> label <> String.duplicate("─", pad - left), :separator}]
  end

  # A new day since the last message (or the first message) warrants a date rule; a non-`DateTime`
  # timestamp can't be compared, so it never triggers one.
  defp day_divider?(nil, %DateTime{}), do: true

  defp day_divider?(%DateTime{} = last, %DateTime{} = at),
    do: Date.compare(DateTime.to_date(at), DateTime.to_date(last)) != :eq

  defp day_divider?(_last, _at), do: false

  # More than five minutes since the last message re-anchors a fresh header, even from one speaker.
  defp gap?(%DateTime{} = last, %DateTime{} = at), do: DateTime.diff(at, last) > 300
  defp gap?(_last, _at), do: false

  # A stable per-author truecolor run style: the operator reads `:operator` pink, a known
  # coworker its hand-picked slot, any other voice a hash onto the palette so it keeps its colour.
  defp author_style(author) do
    if Server.Channel.operator?(author) do
      :operator
    else
      fg = Map.get_lazy(@known, author, fn -> Enum.at(@palette, rem(:erlang.phash2(author), length(@palette))) end)
      {:rgb, fg, Console.Style.bg()}
    end
  end

  defp time(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M")
  defp time(_at), do: "--:--"
end
