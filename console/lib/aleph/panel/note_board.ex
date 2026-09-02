defmodule Console.Panel.NoteBoard do
  @moduledoc """
  The Notes board (Slice D4): a scope's freeform notes as gutter-cards — the first body line as the
  headline with an author-coloured byline, continuation lines indented under it. Pure render over
  `%{notes: [%Server.Note{}]}`.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Console.Card

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{notes: []}, rect), do: Console.Panel.clip([line("no notes yet — press n to jot one", :dim)], rect)

  def render(%{notes: notes}, rect) do
    notes
    |> Enum.flat_map(&note_card/1)
    |> Console.Panel.clip(rect)
  end

  def render(_data, rect), do: Console.Panel.clip([], rect)

  # A note as a gutter-card: headline + author byline, continuation lines as the indented body, a gap.
  defp note_card(note) do
    [head | rest] = String.split(note.body || "", "\n")
    byline = if note.author, do: [{"   — #{note.author}", :operator}], else: []
    header = [{head, :normal} | byline]
    body = Enum.map(rest, fn l -> [{l, :dim}] end)

    Card.gutter_card(header, body, :open) ++ [blank()]
  end

  @impl Console.Panel
  def hints(_data), do: [{"n", "new"}, {"esc", "close"}]
end
