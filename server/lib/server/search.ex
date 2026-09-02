defmodule Server.Search do
  @moduledoc """
  Total recall (design: server-total-recall, slice A): FTS5 search over the message channel
  (`history/2` — episodic recall of past sessions) and the fact corpus (`facts/2` — the ledger
  past the brief's cap). The curated brief answers "what should I inherit"; search answers "did we
  ever touch X." Both rank by bm25, return a `%{shown, more}` cut-with-its-count (a cut without a
  count lies), and are read-only over the index the migration's triggers keep in sync.

  The raw query is sanitized into a safe FTS5 MATCH — each whitespace token quoted as a string
  literal, so a user's `-`, `*`, `AND`, or stray `"` is searched for, never interpreted as an FTS5
  operator (which would error or silently change the query).
  """
  alias Server.Repo

  # The default cut — five is the brief's cap; search shows a few more since it's an explicit query.
  @cap 10

  @doc """
  Search the message channel. Returns `%{shown: [%{message_id, thread_id, author, snippet, at}],
  more: n}`, `shown` ranked best-first and capped, `more` the count beyond the cut. A blank query
  returns an empty cut, never an error.
  """
  def history(query, limit \\ @cap) when is_binary(query) do
    case fts_match(query) do
      "" ->
        %{shown: [], more: 0}

      match ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT m.id, m.thread_id, m.author,
                   snippet(message_fts, 0, '⟪', '⟫', '…', 12),
                   m.created_at
            FROM message_fts
            JOIN message m ON m.id = message_fts.rowid
            WHERE message_fts MATCH ?
            ORDER BY bm25(message_fts)
            LIMIT ?
            """,
            [match, limit]
          )

        shown =
          Enum.map(rows, fn [id, thread_id, author, snippet, at] ->
            %{message_id: id, thread_id: thread_id, author: author, snippet: snippet, at: at}
          end)

        %{shown: shown, more: max(count("message_fts", match) - length(shown), 0)}
    end
  end

  @doc """
  Search the fact corpus. Returns `%{shown: [%{fact_id, thread_id, kind, text, snippet, at}],
  more: n}`, ranked + capped like `history/2`.
  """
  def facts(query, limit \\ @cap) when is_binary(query) do
    case fts_match(query) do
      "" ->
        %{shown: [], more: 0}

      match ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT f.id, f.thread_id, f.kind, f.text,
                   snippet(fact_fts, 0, '⟪', '⟫', '…', 12),
                   f.created_at
            FROM fact_fts
            JOIN fact f ON f.id = fact_fts.rowid
            WHERE fact_fts MATCH ? AND f.forgotten_at IS NULL
            ORDER BY bm25(fact_fts)
            LIMIT ?
            """,
            [match, limit]
          )

        shown =
          Enum.map(rows, fn [id, thread_id, kind, text, snippet, at] ->
            %{fact_id: id, thread_id: thread_id, kind: kind, text: text, snippet: snippet, at: at}
          end)

        %{shown: shown, more: max(remembered_fact_count(match) - length(shown), 0)}
    end
  end

  @doc """
  Keyword relevance of each of `fact_ids` to `query` — the keyword half of the recall layer's
  relevance blend (`Server.Recall`). Unlike the searches above, a fact matches on ANY query term
  (the query is a thread's title + the operator's last words, not a hand-typed AND), graded by
  bm25 and normalised so the best match is 1.0 — bm25's idf is what keeps "the" from counting like
  "credential". A map of id => relevance in (0, 1]; unmatched ids are absent; empty for a blank
  query or id list.
  """
  def fact_relevance(query, fact_ids) when is_binary(query) and is_list(fact_ids) do
    case {fts_any(query), fact_ids} do
      {"", _} ->
        %{}

      {_match, []} ->
        %{}

      {match, ids} ->
        id_list = Enum.map_join(ids, ",", &Integer.to_string/1)

        %{rows: rows} =
          Repo.query!(
            "SELECT rowid, bm25(fact_fts) FROM fact_fts WHERE fact_fts MATCH ? AND rowid IN (#{id_list})",
            [match]
          )

        normalise(rows)
    end
  end

  # bm25 scores are negative, best-first; scale to (0, 1] against the best so the top hit is 1.0.
  defp normalise([]), do: %{}

  defp normalise(rows) do
    best = rows |> Enum.map(fn [_id, score] -> score end) |> Enum.min()
    if best == 0, do: Map.new(rows, fn [id, _] -> {id, 1.0} end), else: Map.new(rows, fn [id, s] -> {id, s / best} end)
  end

  defp count(table, match) do
    %{rows: [[n]]} = Repo.query!("SELECT count(*) FROM #{table} WHERE #{table} MATCH ?", [match])
    n
  end

  # Fact matches that are still remembered — `more` must not count tombstoned rows.
  defp remembered_fact_count(match) do
    %{rows: [[n]]} =
      Repo.query!(
        "SELECT count(*) FROM fact_fts JOIN fact f ON f.id = fact_fts.rowid WHERE fact_fts MATCH ? AND f.forgotten_at IS NULL",
        [match]
      )

    n
  end

  # Turn a raw query into a safe FTS5 MATCH: each whitespace token becomes a quoted string literal
  # (inner quotes stripped), so operators/punctuation are searched for, not interpreted. Multiple
  # tokens AND implicitly. An all-blank query yields "" — the callers short-circuit to an empty cut.
  defp fts_match(query), do: query |> fts_tokens() |> Enum.join(" ")

  defp fts_any(query), do: query |> fts_tokens() |> Enum.join(" OR ")

  defp fts_tokens(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(fn token -> ~s("#{String.replace(token, "\"", "")}") end)
    |> Enum.reject(&(&1 == ~s("")))
  end
end
