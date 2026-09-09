defmodule Console.Fuzzy do
  @moduledoc """
  The switcher's and palette's ranking (UX slice 2): a **subsequence** match with a score, the
  shape every fuzzy finder uses — the query's characters must appear in the subject in order,
  never necessarily adjacent, so `fcs` finds `ficciones · #general · cockpit slice`.

  `match/2` is the whole engine. It walks the subject left to right taking the FIRST occurrence of
  each query character (greedy, like fzf's fast path — not the optimal alignment, which costs a
  full DP table for a ranking nobody can tell apart at this list length) and scores each hit:

    * a hit at a **word start** (position 0, or after a separator) is the strongest signal —
      that's the initialism a person types;
    * a hit **immediately after the previous one** is next — a typed prefix;
    * every character skipped costs a little, so a tight, early match outranks a scattered or
      late one.

  Case-insensitive. An empty query matches everything at 0, so an unfiltered list keeps its
  natural order.
  """

  # A word start is the strongest hint (the initialism you actually type); a run is next; every
  # skipped character costs. The three only ever matter relative to each other.
  @bonus_word_start 8
  @bonus_run 6
  @penalty_gap 1

  # What ends a word for @bonus_word_start. The switcher's subjects are `workspace · #channel ·
  # title`, so the separators are the punctuation those paths are built from.
  @separators [" ", "·", "-", "_", "/", ".", ":", "#", "(", ")", "[", "]"]

  @doc """
  Score `subject` against `query`, or `nil` when the query is not a subsequence of it. Higher is
  a better match; an empty query is 0 (everything matches, nothing is preferred).
  """
  @spec match(String.t(), String.t()) :: integer() | nil
  def match(subject, query) do
    case String.downcase(query) |> String.graphemes() do
      [] -> 0
      q -> walk(String.downcase(subject) |> String.graphemes(), q, nil, 0, 0, nil)
    end
  end

  # `prev` is the subject index of the last hit (nil before the first), `i` the cursor, `score` the
  # running total, `prev_char` the grapheme before the cursor (for the word-start test).
  defp walk(_subject, [], _prev, _i, score, _prev_char), do: score
  defp walk([], _query, _prev, _i, _score, _prev_char), do: nil

  defp walk([c | rest], [c | q_rest], prev, i, score, prev_char),
    do: walk(rest, q_rest, i, i + 1, score + hit_bonus(prev, i, prev_char), c)

  defp walk([c | rest], query, prev, i, score, _prev_char),
    do: walk(rest, query, prev, i + 1, score - @penalty_gap, c)

  defp hit_bonus(prev, i, prev_char) do
    cond do
      i == 0 or prev_char in @separators -> @bonus_word_start
      prev == i - 1 -> @bonus_run
      true -> 0
    end
  end

  @doc """
  Rank `entries` against `query`, dropping the ones that don't match. `subject` extracts the text
  to match (default: the entry itself). Ties break on the shorter subject, then on the input
  order — so an unfiltered list is exactly the list handed in.
  """
  @spec filter([e], String.t(), (e -> String.t())) :: [e] when e: term()
  def filter(entries, query, subject \\ & &1)

  # No query, no ranking: every entry scores 0, so sorting would only shuffle them by length.
  def filter(entries, "", _subject), do: entries

  def filter(entries, query, subject) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, i} ->
      text = subject.(entry)

      case match(text, query) do
        nil -> []
        score -> [{-score, String.length(text), i, entry}]
      end
    end)
    |> Enum.sort()
    |> Enum.map(fn {_score, _len, _i, entry} -> entry end)
  end
end
