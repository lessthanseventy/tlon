defmodule Console.Text do
  @moduledoc "Tiny text helpers for panels: greedy word-wrap to a column width."

  @doc """
  Wrap `string` to `width` graphemes, breaking on spaces where possible and hard-breaking
  a word longer than the column. Returns a list of lines. An empty string yields `[]`.
  """
  @spec wrap(String.t(), pos_integer()) :: [String.t()]
  def wrap(string, width) when width > 0 do
    string
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([], fn word, lines -> place(word, lines, width) end)
    |> Enum.reverse()
  end

  # No line in progress, or the word fits on the current line with a space: extend it.
  defp place(word, [], width), do: word |> hard_break(width) |> Enum.reverse()

  defp place(word, [current | rest], width) do
    cond do
      String.length(current) + 1 + String.length(word) <= width ->
        [current <> " " <> word | rest]

      String.length(word) <= width ->
        [word, current | rest]

      true ->
        # word longer than the column — hard-break it, newest chunk stays current.
        (word |> hard_break(width) |> Enum.reverse()) ++ [current | rest]
    end
  end

  defp hard_break(word, width) do
    word |> String.graphemes() |> Enum.chunk_every(width) |> Enum.map(&Enum.join/1)
  end

  @doc """
  Wrap an INPUT buffer to `width` without changing it: every grapheme (spaces included) lands on
  some line, so `Enum.join(lines) == string`. Breaks after the last space that fits, else hard.
  The reply box and the new-thread band use this — what you typed is what you see; `wrap/2`
  collapses whitespace and is for prose (2026-09-08). An empty string is one empty line.
  """
  @spec wrap_exact(String.t(), pos_integer()) :: [String.t()]
  def wrap_exact(string, width) when width > 0 do
    string |> String.graphemes() |> exact_lines(width, []) |> Enum.reverse()
  end

  defp exact_lines([], _width, []), do: [""]
  defp exact_lines([], _width, acc), do: acc

  defp exact_lines(graphemes, width, acc) do
    {line, rest} = Enum.split(graphemes, width)

    {line, rest} =
      case {rest, line |> Enum.reverse() |> Enum.find_index(&(&1 == " "))} do
        # the whole remainder fits, or no space to break after — take the chunk as is
        {[], _} ->
          {line, rest}

        {_, nil} ->
          {line, rest}

        # break AFTER the last space in reach; the space stays on this line
        {_, from_end} ->
          keep = width - from_end
          {Enum.take(line, keep), Enum.drop(line, keep) ++ rest}
      end

    exact_lines(rest, width, [Enum.join(line) | acc])
  end

  @doc """
  Paragraph-aware wrap: hard newlines keep their breaks (each line wraps separately, so lists
  survive), and a run of blank lines becomes exactly ONE empty line between paragraphs — the
  author's paragraph structure renders instead of collapsing. An empty string yields `[]`.
  """
  @spec wrap_paragraphs(String.t(), pos_integer()) :: [String.t()]
  def wrap_paragraphs(string, width) when width > 0 do
    string
    |> String.split("\n")
    |> Enum.chunk_by(&blank_line?/1)
    |> Enum.reject(fn [first | _] -> blank_line?(first) end)
    |> Enum.map(fn paragraph -> Enum.flat_map(paragraph, &wrap(&1, width)) end)
    |> Enum.reject(&(&1 == []))
    |> Enum.intersperse([""])
    |> Enum.concat()
  end

  defp blank_line?(line), do: String.trim(line) == ""

  @doc """
  A ticking elapsed-time label, deliberately sub-minute-precise (unlike
  `Console.Stack.relative_time/2`'s "5 minutes ago" bucketing) so a presence indicator visibly counts
  up between renders instead of reading as frozen. Past an hour it drops the seconds; negative input
  (clock skew) clamps to `"0s"`.

      iex> Console.Text.duration(45)
      "45s"

      iex> Console.Text.duration(72)
      "1m12s"

      iex> Console.Text.duration(3900)
      "1h5m"

      iex> Console.Text.duration(-5)
      "0s"
  """
  @spec duration(integer()) :: String.t()
  def duration(seconds) when seconds < 0, do: duration(0)
  def duration(seconds) when seconds < 60, do: "#{seconds}s"
  def duration(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m#{rem(seconds, 60)}s"
  def duration(seconds), do: "#{div(seconds, 3_600)}h#{div(rem(seconds, 3_600), 60)}m"
end
