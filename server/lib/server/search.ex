defmodule Server.Search do
  @moduledoc """
  Total recall (design: server-total-recall, slice A): full-text search over the message channel
  (`history/2` — episodic recall of past sessions) and the fact corpus (`facts/2` — the ledger
  past the brief's cap). The curated brief answers "what should I inherit"; search answers "did we
  ever touch X." Both rank (Postgres `ts_rank_cd` over a generated `tsvector`, one-brain piece C —
  was FTS5 bm25), return a `%{shown, more}` cut-with-its-count (a cut without a count lies), and
  are read-only over the generated column the baseline keeps in sync.

  The raw query is never interpreted as query syntax: `plainto_tsquery` treats every token as a
  literal term and ANDs them; `fact_relevance/2` ORs them (`websearch_to_tsquery` with `or`).
  """
  alias Server.Repo

  # The default cut — five is the brief's cap; search shows a few more since it's an explicit query.
  @cap 10

  @headline "StartSel=⟪, StopSel=⟫, MaxWords=12, MinWords=4, MaxFragments=1, FragmentDelimiter=…"

  @doc """
  Search the message channel. Returns `%{shown: [%{message_id, thread_id, author, snippet, at}],
  more: n}`, `shown` ranked best-first and capped, `more` the count beyond the cut. A blank query
  returns an empty cut, never an error.
  """
  def history(query, limit \\ @cap) when is_binary(query) do
    case terms(query) do
      "" ->
        %{shown: [], more: 0}

      q ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT m.id, m.thread_id, m.author,
                   ts_headline('english', m.body, plainto_tsquery('english', $1), $3),
                   m.created_at
            FROM message m
            WHERE m.body_tsv @@ plainto_tsquery('english', $1)
            ORDER BY ts_rank_cd(m.body_tsv, plainto_tsquery('english', $1)) DESC, m.id DESC
            LIMIT $2
            """,
            [q, limit, @headline]
          )

        shown =
          Enum.map(rows, fn [id, thread_id, author, snippet, at] ->
            %{message_id: id, thread_id: thread_id, author: author, snippet: snippet, at: at}
          end)

        %{shown: shown, more: max(count("message", "body_tsv", q, "") - length(shown), 0)}
    end
  end

  @doc """
  Search the fact corpus. Returns `%{shown: [%{fact_id, thread_id, kind, text, snippet, at}],
  more: n}`, ranked + capped like `history/2`. Tombstoned (forgotten) facts are never returned
  nor counted.
  """
  def facts(query, limit \\ @cap) when is_binary(query) do
    case terms(query) do
      "" ->
        %{shown: [], more: 0}

      q ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT f.id, f.thread_id, f.kind, f.text,
                   ts_headline('english', f.text, plainto_tsquery('english', $1), $3),
                   f.created_at
            FROM fact f
            WHERE f.text_tsv @@ plainto_tsquery('english', $1) AND f.forgotten_at IS NULL
            ORDER BY ts_rank_cd(f.text_tsv, plainto_tsquery('english', $1)) DESC, f.id DESC
            LIMIT $2
            """,
            [q, limit, @headline]
          )

        shown =
          Enum.map(rows, fn [id, thread_id, kind, text, snippet, at] ->
            %{fact_id: id, thread_id: thread_id, kind: kind, text: text, snippet: snippet, at: at}
          end)

        %{shown: shown, more: max(count("fact", "text_tsv", q, "AND forgotten_at IS NULL") - length(shown), 0)}
    end
  end

  @doc """
  Keyword relevance of each of `fact_ids` to `query` — the keyword half of the recall layer's
  relevance blend (`Server.Recall`). Unlike the searches above, a fact matches on ANY query term
  (the query is a thread's title + the operator's last words, not a hand-typed AND), graded by
  `ts_rank_cd` and normalised so the best match is 1.0. A map of id => relevance in (0, 1];
  unmatched ids are absent; empty for a blank query or id list.
  """
  def fact_relevance(query, fact_ids) when is_binary(query) and is_list(fact_ids) do
    case {any_terms(query), fact_ids} do
      {"", _} ->
        %{}

      {_q, []} ->
        %{}

      {q, ids} ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT id, ts_rank_cd(text_tsv, websearch_to_tsquery('english', $1))
            FROM fact
            WHERE id = ANY($2) AND text_tsv @@ websearch_to_tsquery('english', $1)
            """,
            [q, ids]
          )

        normalise(rows)
    end
  end

  # ts_rank_cd is positive, best-highest; scale to (0, 1] against the best so the top hit is 1.0.
  defp normalise([]), do: %{}

  defp normalise(rows) do
    best = rows |> Enum.map(fn [_id, score] -> score end) |> Enum.max()
    if best == 0, do: Map.new(rows, fn [id, _] -> {id, 1.0} end), else: Map.new(rows, fn [id, s] -> {id, s / best} end)
  end

  defp count(table, column, q, extra) do
    %{rows: [[n]]} =
      Repo.query!("SELECT count(*) FROM #{table} WHERE #{column} @@ plainto_tsquery('english', $1) #{extra}", [q])

    n
  end

  # The literal terms, whitespace-joined: plainto_tsquery ANDs them and treats punctuation as text,
  # so a user's `-`, `*`, `AND` or stray `"` is searched for, never interpreted.
  defp terms(query), do: query |> tokens() |> Enum.join(" ")

  # The same terms, OR-joined for websearch_to_tsquery (its `or` is the one operator it knows).
  defp any_terms(query), do: query |> tokens() |> Enum.join(" or ")

  defp tokens(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.replace(&1, "\"", ""))
    |> Enum.reject(&(&1 == "" or String.downcase(&1) == "or"))
  end
end
