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
  A ticking elapsed-time label: `"45s"` under a minute, `"3m12s"` under an hour, `"1h05m"`
  beyond — deliberately sub-minute-precise (unlike `Console.Stack.relative_time/2`'s "5 minutes
  ago" bucketing) so a presence indicator visibly counts up between renders instead of reading
  as frozen. Negative input (clock skew) clamps to `"0s"`.
  """
  @spec duration(integer()) :: String.t()
  def duration(seconds) when seconds < 0, do: duration(0)
  def duration(seconds) when seconds < 60, do: "#{seconds}s"
  def duration(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m#{rem(seconds, 60)}s"
  def duration(seconds), do: "#{div(seconds, 3_600)}h#{div(rem(seconds, 3_600), 60)}m"
end
