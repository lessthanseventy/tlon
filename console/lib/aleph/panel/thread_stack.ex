defmodule Console.Panel.ThreadStack do
  @moduledoc """
  The cockpit center (Slice 3, 2026-08-30): a vertical stack of Slack-style thread cards. Each card
  is **folded** (a one-line header — so a stack of folded cards IS the thread list) or **unfolded**
  (`z` — the conversation + a per-thread reply input). The active thread is unfolded by default.

  Styling: the active card carries an accent gutter (`▌`) and a bright header; folded/inactive cards
  are quiet. Messages are nested under the header, author-coloured and paragraph-wrapped (the same
  quality as `Console.Panel.Conversation`), with breathing room between them and between cards.

  Data is `%{cards: [card]}`, a card `%{id, title, lead, stage, awaiting, folded?, active?, messages}`
  (`messages` a list of `%{author, body}`, read only when unfolded). Pure render.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  @indent "    "
  @recent 6

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{cards: []}, rect),
    do: Console.Panel.clip([blank(), line("  no threads yet — press : to file a ticket or start one", :dim)], rect)

  def render(%{cards: cards}, rect) do
    cards
    |> Enum.map(&card_block(&1, rect.w))
    |> Enum.intersperse([blank()])
    |> Enum.concat()
    |> Console.Panel.clip(rect)
  end

  @impl Console.Panel
  def hints(_data), do: [{"z", "fold"}, {"Z", "zoom"}, {"j/k", "move"}, {"c", "reply"}]

  # Click → the card under `local_y` (walking the same row layout render produces) → fold/focus it.
  @impl Console.Panel
  def pick(%{cards: cards}, rect, local_y) do
    {_offset, hit} =
      cards
      |> Enum.intersperse(:gap)
      |> Enum.reduce_while({0, nil}, fn
        :gap, {offset, _} ->
          {:cont, {offset + 1, nil}}

        card, {offset, _} ->
          height = length(card_block(card, rect.w))
          if local_y >= offset and local_y < offset + height, do: {:halt, {offset, {:fold_thread, card.id}}}, else: {:cont, {offset + height, nil}}
      end)

    hit
  end

  def pick(_data, _rect, _local_y), do: nil

  # -- card layout ----------------------------------------------------------

  defp card_block(%{folded?: true} = card, w), do: [header_row(card, w)]

  defp card_block(%{folded?: false} = card, w) do
    body =
      case message_lines(card[:messages] || [], w) do
        [] -> [line("#{@indent}no messages yet", :dim)]
        lines -> lines
      end

    [header_row(card, w), blank()] ++ body ++ [blank(), reply_row(card)]
  end

  # `▌ ▾ #2  title            @lead · [stage] · ⏸ gate` — the active card lit, the rest quiet.
  defp header_row(%{active?: true} = card, _w) do
    [{"▌ ", :accent}, {"▾ ", :accent}, {"##{card.id} ", :header}, {card.title, :header}] ++ chips(card)
  end

  defp header_row(card, _w) do
    marker = if card.folded?, do: "▸ ", else: "▾ "
    [{"  ", :normal}, {marker, :dim}, {"##{card.id} ", :dim}, {card.title, :normal}] ++ chips(card)
  end

  defp chips(card) do
    lead = if card[:lead], do: [{"  @#{card.lead}", :label}], else: []
    stage = if card[:stage], do: [{" · #{card.stage}", :dim}], else: []
    awaiting = if card[:awaiting] not in [nil, ""], do: [{" · ⏸ #{card.awaiting}", :accent}], else: []
    lead ++ stage ++ awaiting
  end

  # The last few messages, author-coloured + paragraph-wrapped + nested, a blank line between each.
  defp message_lines([], _w), do: []

  defp message_lines(messages, w) do
    messages
    |> Enum.take(-@recent)
    |> Enum.map(&message_rows(&1, w))
    |> Enum.reject(&(&1 == []))
    |> Enum.intersperse([blank()])
    |> Enum.concat()
  end

  # A message as a chat bubble: the author on its own line, then the body rendered as MARKDOWN
  # (Console.Markdown — bold/code/lists/headings), each row indented under the author. Reads like a
  # chat, not a wall of text: the old `one_line/1` flattened the whole body onto one wrapped line.
  defp message_rows(%{author: author, body: body}, w) do
    operator? = Server.Channel.operator?(author)
    author_style = if operator?, do: :operator, else: :label
    base = if operator?, do: :operator, else: :normal

    body_rows =
      body
      |> Console.Markdown.render(max(w - String.length(@indent), 1), base)
      |> Enum.map(fn
        [] -> []
        row -> [{@indent, base} | row]
      end)

    [[{"#{author}:", author_style}] | body_rows]
  end

  defp reply_row(card), do: [{"#{@indent}↳ ", :accent}, {"reply to ##{card.id}… (c)", :dim}]
end
