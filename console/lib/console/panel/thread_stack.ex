defmodule Console.Panel.ThreadStack do
  @moduledoc """
  The cockpit center: the OPEN thread's conversation, scrollable and text-selectable. It is never a
  list — the rail is the list — so with nothing open it is one line pointing there. Replying is a
  separate persistent band below (`Console.Panel.Reply`), focused the moment a thread opens; this
  panel is read-only backlog. Messages are nested under the header, author-coloured and
  paragraph-wrapped, with breathing room between them.

  Data is `%{cards: [card], opened: id | nil}`, a card `%{id, title, lead, stage, awaiting,
  messages}` (`messages` a list of `%{author, body}`, read only for the opened thread). Pure render.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  @indent "    "
  @recent 6

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{cards: []}, rect),
    do: Console.Panel.clip([blank(), line("  no threads yet — press n to start one", :dim)], rect)

  def render(%{cards: cards, opened: opened} = data, rect) when is_integer(opened) do
    case Enum.find(cards, &(&1.id == opened)) do
      nil -> render(Map.delete(data, :opened), rect)
      card -> conversation(card, rect)
    end
  end

  def render(%{cards: _cards}, rect) do
    Console.Panel.clip(
      [blank(), line("  pick a thread on the rail — j/k, ⏎", :dim), line("    n starts a new one", :dim)],
      rect
    )
  end

  @impl Console.Panel
  def hints(%{opened: opened}) when is_integer(opened), do: [{"type", "reply"}, {"⇞⇟", "scroll"}, {"esc", "back"}]
  def hints(_data), do: [{"n", "new"}]

  defp conversation(card, rect) do
    body =
      case message_lines(card[:messages] || [], rect.w) do
        [] -> [line("#{@indent}no messages yet", :dim)]
        lines -> lines
      end

    header = [[{"‹ ", :accent}, {"##{card.id} #{card.title}", :header}] ++ chips(card), blank()]
    Console.Panel.clip(header ++ body ++ typing_line(card), rect)
  end

  # Under the last message, not in the header: the indicator promises a message, so it belongs
  # where that message will land.
  defp typing_line(%{typing: who}) when is_binary(who), do: [line("#{@indent}#{who} is typing…", :st_working)]
  defp typing_line(_card), do: []

  # The header's chips: lead, stage, a parked gate. Typing is not one of them — it belongs under the
  # last message, where the message it promises will land (`typing_line/1`).
  defp chips(card) do
    lead = if card[:lead], do: [{"  @#{card.lead}", :label}], else: []
    stage = if card[:stage], do: [{" · #{card.stage}", :dim}], else: []
    awaiting = if card[:awaiting] in [nil, ""], do: [], else: [{" · ⏸ #{card.awaiting}", :accent}]

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

  # A frozen pane (Server.Attention.Stall): open, it reads as tlon's post; resolved, a receipt.
  defp message_rows(%{kind: "stall", body: body, resolution: resolution}, _w) when is_binary(resolution) do
    [[{"#{body} — #{resolution}", :dim}]]
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
