defmodule Console.Panel.ThreadStack do
  @moduledoc """
  The cockpit center (Slice 3, 2026-08-30): a two-step master⇄detail. With no thread `opened` it's a
  clean LIST (one row per thread — a stack of headers IS the thread list); with a thread opened it's
  that ONE conversation, scrollable and text-selectable. Replying is a separate persistent band below
  (`Console.Panel.Reply`), focused the moment a thread opens — this panel is read-only backlog.

  Styling: the active row carries an accent gutter (`▌`) and a bright header; inactive rows are quiet.
  Messages are nested under the header, author-coloured and paragraph-wrapped, with breathing room
  between them.

  Data is `%{cards: [card], opened: id | nil}`, a card `%{id, title, lead, stage, awaiting, active?,
  messages}` (`messages` a list of `%{author, body}`, read only for the opened thread). Pure render.
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
  def hints(%{opened: opened}) when is_integer(opened), do: [{"type", "reply"}, {"⇞⇟", "scroll"}, {"esc", "back"}]
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

    header = [[{"‹ ", :accent}, {"##{card.id} #{card.title}", :header}] ++ chips(card, typing: false), blank()]
    footer = [blank(), line("#{@indent}esc · back to threads", :dim)]

    Console.Panel.clip(header ++ body ++ typing_line(card) ++ footer, rect)
  end

  # Under the last message, not in the header: the indicator promises a message, so it belongs
  # where that message will land.
  defp typing_line(%{typing: who}) when is_binary(who), do: [line("#{@indent}#{who} is typing…", :st_working)]
  defp typing_line(_card), do: []

  # On the one-line LIST row the typing signal has nowhere to go but the row. In the CONVERSATION it
  # belongs at the bottom instead — under the last message, where the message it promises will
  # actually appear — so that caller asks for `typing: false` and renders `typing_line/1` itself.
  defp chips(card, opts \\ []) do
    lead = if card[:lead], do: [{"  @#{card.lead}", :label}], else: []
    stage = if card[:stage], do: [{" · #{card.stage}", :dim}], else: []
    awaiting = if card[:awaiting] in [nil, ""], do: [], else: [{" · ⏸ #{card.awaiting}", :accent}]

    typing =
      if card[:typing] && Keyword.get(opts, :typing, true),
        do: [{" · #{card.typing} is typing…", :st_working}],
        else: []

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

  # A coworker waiting on the operator (Server.Attention): the ask, then its options on one line —
  # the reply box answers with a key. Once resolved it reads as a quiet receipt.
  defp message_rows(%{kind: "prompt", payload: %{"summary" => summary, "options" => options}, resolved_at: nil}, w) do
    keys = Enum.map_join(options, " · ", &"(#{&1["key"]}) #{&1["label"]}")

    [
      [{"⚑ waiting on you — #{summary}", :st_await}]
      | Enum.map(Console.Text.wrap(keys, max(w - String.length(@indent), 1)), &[{@indent <> &1, :dim}])
    ]
  end

  defp message_rows(%{kind: "prompt", payload: %{"summary" => summary}, resolution: resolution}, _w) do
    [[{"⚑ #{summary} — #{resolution}", :dim}]]
  end

  # A message as a chat bubble: the author on its own line, then the body rendered as MARKDOWN
  # (Console.Markdown — bold/code/lists/headings), each row indented under the author. Reads like a
  # chat, not a wall of text: the old `one_line/1` flattened the whole body onto one wrapped line.
  defp message_rows(%{author: author, body: body}, w) do
    operator? = Console.Server.Channel.operator?(author)
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
end
