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

  # Two-step master⇄detail (2026-09-01, Andrew): with no thread `opened`, the center is a clean LIST
  # (one line per thread, pick to enter); with a thread opened it's that ONE conversation — scrollable,
  # text-selectable (clicks no longer toggle anything), markdown. Esc goes back to the list.
  @impl Console.Panel
  def render(%{cards: []}, rect),
    do: Console.Panel.clip([blank(), line("  no threads yet — press n to start one", :dim)], rect)

  def render(%{cards: cards, opened: opened} = data, rect) when is_integer(opened) do
    case Enum.find(cards, &(&1.id == opened)) do
      nil -> render(Map.delete(data, :opened), rect)
      card -> conversation(card, rect)
    end
  end

  def render(%{cards: cards}, rect) do
    cards |> Enum.map(&list_row(&1, rect.w)) |> Console.Panel.clip(rect)
  end

  @impl Console.Panel
  def hints(%{opened: opened}) when is_integer(opened), do: [{"esc", "back"}, {"c", "reply"}, {"j/k", "scroll"}]
  def hints(_data), do: [{"⏎", "open"}, {"j/k", "move"}, {"n", "new"}]

  # LIST: one row per thread, so `local_y` indexes the card directly → OPEN it (not fold).
  @impl Console.Panel
  def pick(%{opened: opened}, _rect, _local_y) when is_integer(opened), do: nil

  def pick(%{cards: cards}, _rect, local_y) do
    case Enum.at(cards, local_y) do
      %{id: id} -> {:open_thread_view, id}
      _ -> nil
    end
  end

  def pick(_data, _rect, _local_y), do: nil

  # -- list ----------------------------------------------------------------

  # A compact one-line thread row: `▌ #7 title   @lead · stage · …typing`, the active one lit.
  defp list_row(card, w) do
    cursor = if card.active?, do: {"▌ ", :accent}, else: {"  ", :normal}
    id_style = if card.active?, do: :header, else: :dim
    title_style = if card.active?, do: :header, else: :normal
    [cursor, {"##{card.id} ", id_style}, {String.slice(card.title || "", 0, max(w - 24, 8)), title_style}] ++ chips(card)
  end

  # -- conversation --------------------------------------------------------

  defp conversation(card, rect) do
    body =
      case message_lines(card[:messages] || [], rect.w) do
        [] -> [line("#{@indent}no messages yet", :dim)]
        lines -> lines
      end

    header = [[{"‹ ", :accent}, {"##{card.id} #{card.title}", :header}] ++ chips(card), blank()]
    footer = [blank(), reply_row(card), line("#{@indent}esc · back to threads", :dim)]

    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp chips(card) do
    lead = if card[:lead], do: [{"  @#{card.lead}", :label}], else: []
    stage = if card[:stage], do: [{" · #{card.stage}", :dim}], else: []
    awaiting = if card[:awaiting] not in [nil, ""], do: [{" · ⏸ #{card.awaiting}", :accent}], else: []
    # A live "…typing" signal while the lead is composing (declared thinking presence).
    typing = if card[:typing], do: [{" · #{card.typing} is typing…", :st_working}], else: []
    lead ++ stage ++ awaiting ++ typing
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
