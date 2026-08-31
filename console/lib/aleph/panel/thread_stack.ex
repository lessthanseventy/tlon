defmodule Console.Panel.ThreadStack do
  @moduledoc """
  The cockpit center (Slice 3, 2026-08-30): a vertical stack of Slack-style thread cards. Each
  card is **folded** (a one-line header — so a stack of folded cards IS the thread list) or
  **unfolded** (`z` — the full conversation + a per-thread reply input). The active thread is
  unfolded by default. This replaces the single follow-focus conversation/terminal center: folding
  is the list-vs-detail split, collapsed into one surface.

  Data is `%{cards: [card]}` where a card is
  `%{id, title, lead, stage, awaiting, folded?, active?, messages}` (`messages` a list of
  `%{author, body}`, only read when unfolded). Pure render — the cockpit assembles the cards
  (threads + fold set + messages) so this stays testable without a live channel.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{cards: []}, rect), do: Console.Panel.clip([line("no threads yet", :dim)], rect)

  def render(%{cards: cards}, rect) do
    cards
    |> Enum.flat_map(&card_rows(&1, rect.w))
    |> Console.Panel.clip(rect)
  end

  @impl Console.Panel
  def hints(_data), do: [{"z", "fold"}, {"Z", "zoom"}, {"j/k", "move"}, {"c", "reply"}]

  # Click → the card under `local_y` (walking the same row layout render produces) → fold/focus it.
  @impl Console.Panel
  def pick(%{cards: cards}, rect, local_y) do
    {_offset, hit} =
      Enum.reduce_while(cards, {0, nil}, fn card, {offset, _} ->
        height = length(card_rows(card, rect.w))

        if local_y >= offset and local_y < offset + height,
          do: {:halt, {offset, {:fold_thread, card.id}}},
          else: {:cont, {offset + height, nil}}
      end)

    hit
  end

  def pick(_data, _rect, _local_y), do: nil

  # A folded card is just its header; an unfolded one adds its messages + a reply input, then a gap.
  defp card_rows(%{folded?: true} = card, _w), do: [header_row(card)]

  defp card_rows(%{folded?: false} = card, w) do
    [header_row(card)] ++ message_rows(card[:messages] || [], w) ++ [reply_row(card), blank()]
  end

  defp header_row(card) do
    marker = if card.folded?, do: "▸ ", else: "▾ "
    title_style = if card[:active?], do: :selected, else: :normal

    [{marker, :accent}, {"##{card.id} #{card.title}", title_style}] ++ chips(card)
  end

  # ` · @lead · [stage]` / ` · ⏸ awaiting` — each omitted when absent.
  defp chips(card) do
    lead = if card[:lead], do: [{" · @#{card.lead}", :dim}], else: []
    stage = if card[:stage], do: [{" · [#{card.stage}]", :dim}], else: []
    awaiting = if card[:awaiting] not in [nil, ""], do: [{" · ⏸ #{card.awaiting}", :accent}], else: []
    lead ++ stage ++ awaiting
  end

  # Last few messages, one truncated line each ("  author: body"), so an unfolded card stays compact.
  defp message_rows([], _w), do: [line("  no messages yet", :dim)]

  defp message_rows(messages, w) do
    messages
    |> Enum.take(-6)
    |> Enum.map(fn %{author: author, body: body} ->
      style = if Server.Channel.operator?(author), do: :operator, else: :normal
      [{"  ", :normal}, {truncate("#{author}: #{one_line(body)}", w - 2), style}]
    end)
  end

  defp reply_row(card), do: [{"  ‹reply to ##{card.id}…›", :dim}]

  defp one_line(body), do: body |> to_string() |> String.replace("\n", " ")

  defp truncate(s, max) when max <= 1, do: s
  defp truncate(s, max) do
    if String.length(s) > max, do: String.slice(s, 0, max - 1) <> "…", else: s
  end
end
