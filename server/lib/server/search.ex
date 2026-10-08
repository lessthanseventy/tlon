defmodule Server.Search do
  @moduledoc """
  Total recall (design: server-total-recall, slice A): full-text search over the message channel
  (`history/3` — episodic recall of past sessions) and the fact corpus (`facts/2` — the ledger
  past the brief's cap). The curated brief answers "what should I inherit"; search answers "did we
  ever touch X." `history/3` fuses two rankings by reciprocal rank: BM25 over a generated `tsvector`
  (a rare word outweighs a common one, repeats saturate, a long message does not win by bulk; k1 =
  1.2, b = 0.75) and cosine over the messages' embeddings, so a message that shares the question's
  meaning but none of its words is still found. `facts/2`, whose one-line facts gain little from
  either, ranks by `ts_rank_cd`. Both return a `%{shown, more}` cut-with-its-count (a cut without a
  count lies; `more` counts the keyword matches left out).

  The raw query is never interpreted as query syntax: every token is a literal term, and every
  search matches ANY of them (`websearch_to_tsquery` with `or`) — an agent searches with a whole
  question, and requiring every word of it matches almost nothing.
  """
  alias Server.Recall.Embedding
  alias Server.Repo

  # The default cut — five is the brief's cap; search shows a few more since it's an explicit query.
  @cap 10

  # Each ranker's candidates before fusion, and the standard reciprocal-rank-fusion constant.
  @pool 50
  @rrf_k 60

  @headline "StartSel=⟪, StopSel=⟫, MaxWords=12, MinWords=4, MaxFragments=1, FragmentDelimiter=…"

  @doc """
  Search the message channel. Returns `%{shown: [%{message_id, thread_id, author, snippet, at}],
  more: n}`, `shown` ranked best-first and capped, `more` the count beyond the cut. A blank query
  returns an empty cut, never an error. `query_embedding:` supplies the query's vector (else it is
  embedded when any message has one). `around: n` adds each hit's `window`: the hit and up to `n`
  messages either side of it in its own thread, in order, as `%{message_id, author, body, at}` — a
  message is half an exchange, and its answer or question is usually the next or last one.
  """
  def history(query, limit \\ @cap, opts \\ []) when is_binary(query) do
    case any_terms(query) do
      "" ->
        %{shown: [], more: 0}

      q ->
        %{rows: keyword} =
          Repo.query!(
            """
            WITH terms AS (
              SELECT DISTINCT lex FROM unnest(tsvector_to_array(to_tsvector('english', $1))) AS lex
            ),
            stats AS (
              SELECT count(*)::float8 AS n, coalesce(avg(length(body_tsv)), 1)::float8 AS avgdl FROM message
            ),
            idf AS (
              SELECT t.lex, ln(1 + (s.n - df.c + 0.5) / (df.c + 0.5)) AS w
              FROM terms t CROSS JOIN stats s,
              LATERAL (SELECT count(*)::float8 AS c FROM message
                       WHERE body_tsv @@ to_tsquery('simple', quote_literal(t.lex))) df
            )
            SELECT m.id
            FROM message m CROSS JOIN stats s
            WHERE m.body_tsv @@ websearch_to_tsquery('english', $1)
            ORDER BY (
              SELECT coalesce(sum(i.w * cardinality(v.positions) * 2.2 /
                (cardinality(v.positions) + 1.2 * (0.25 + 0.75 * length(m.body_tsv) / s.avgdl))), 0)
              FROM unnest(m.body_tsv) AS v(lexeme, positions, weights) JOIN idf i ON i.lex = v.lexeme
            ) DESC, m.id DESC
            LIMIT $2
            """,
            [q, @pool]
          )

        ids =
          [Enum.map(keyword, &hd/1), semantic_ranked(query, opts)]
          |> fuse()
          |> Enum.take(limit)

        shown = ids |> details(q) |> with_window(Keyword.get(opts, :around, 0))

        %{shown: shown, more: max(count("message", "body_tsv", q, "") - length(shown), 0)}
    end
  end

  @doc """
  Search the fact corpus. Returns `%{shown: [%{fact_id, thread_id, kind, text, snippet, at}],
  more: n}`, ranked + capped like `history/3`. Tombstoned (forgotten) facts are never returned
  nor counted.
  """
  def facts(query, limit \\ @cap) when is_binary(query) do
    case any_terms(query) do
      "" ->
        %{shown: [], more: 0}

      q ->
        %{rows: rows} =
          Repo.query!(
            """
            SELECT f.id, f.thread_id, f.kind, f.text,
                   ts_headline('english', f.text, websearch_to_tsquery('english', $1), $3),
                   f.created_at
            FROM fact f
            WHERE f.text_tsv @@ websearch_to_tsquery('english', $1) AND f.forgotten_at IS NULL
            ORDER BY ts_rank_cd(f.text_tsv, websearch_to_tsquery('english', $1)) DESC, f.id DESC
            LIMIT $2
            """,
            [q, limit, @headline]
          )

        shown =
          Enum.map(rows, fn [id, thread_id, kind, text, snippet, at] ->
            %{fact_id: id, thread_id: thread_id, kind: kind, text: text, snippet: snippet, at: at}
          end)

        %{
          shown: shown,
          more: max(count("fact", "text_tsv", q, "AND forgotten_at IS NULL") - length(shown), 0)
        }
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

  # Every message with an embedding, ranked by cosine to the query's. The query is embedded only
  # when there is something to compare it with, and a down embedder degrades to keyword alone within
  # the same bound recall gives it. Cosine is computed here, not in SQL, so any Postgres will do.
  defp semantic_ranked(query, opts) do
    rows = Repo.query!("SELECT id, embedding FROM message WHERE embedding IS NOT NULL").rows
    vec = rows != [] && (opts[:query_embedding] || query_vector(query))
    if vec, do: by_cosine(rows, vec), else: []
  end

  defp by_cosine(rows, vec) do
    rows
    |> Enum.map(fn [id, json] -> {id, Embedding.cosine(vec, JSON.decode!(json))} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(@pool)
    |> Enum.map(&elem(&1, 0))
  end

  defp query_vector(query) do
    model = get_in(Application.get_env(:server, :embedding, []), [:model]) || "nomic-embed-text"

    case Embedding.embed(query, model: model, timeout: 1_000) do
      {:ok, vec} -> vec
      {:error, _} -> nil
    end
  end

  # Reciprocal rank fusion: each list votes 1 / (k + rank) for what it ranked, so a message both
  # rankers put high beats one either put first alone, and no score scale has to be reconciled.
  defp fuse(lists) do
    lists
    |> Enum.flat_map(fn ids ->
      ids |> Enum.with_index(1) |> Enum.map(fn {id, rank} -> {id, 1 / (@rrf_k + rank)} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {id, votes} -> {-Enum.sum(votes), -id} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp details([], _q), do: []

  defp details(ids, q) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT id, thread_id, author, ts_headline('english', body, websearch_to_tsquery('english', $2), $3), created_at
        FROM message WHERE id = ANY($1)
        """,
        [ids, q, @headline]
      )

    by_id = Map.new(rows, fn [id | _] = row -> {id, row} end)

    # a message deleted between the match and this read is skipped
    for id <- ids,
        [id, thread_id, author, snippet, at] <- [by_id[id]],
        do: %{message_id: id, thread_id: thread_id, author: author, snippet: snippet, at: at}
  end

  defp with_window(shown, 0), do: shown

  defp with_window(shown, n) do
    Enum.map(shown, fn hit ->
      %{rows: rows} =
        Repo.query!(
          """
          (SELECT id, author, body, created_at FROM message
           WHERE thread_id = $1 AND id < $2 ORDER BY id DESC LIMIT $3)
          UNION ALL (SELECT id, author, body, created_at FROM message WHERE id = $2)
          UNION ALL (SELECT id, author, body, created_at FROM message
           WHERE thread_id = $1 AND id > $2 ORDER BY id LIMIT $3)
          ORDER BY id
          """,
          [hit.thread_id, hit.message_id, n]
        )

      window = Enum.map(rows, fn [id, author, body, at] -> %{message_id: id, author: author, body: body, at: at} end)
      Map.put(hit, :window, window)
    end)
  end

  defp count(table, column, q, extra) do
    %{rows: [[n]]} =
      Repo.query!("SELECT count(*) FROM #{table} WHERE #{column} @@ websearch_to_tsquery('english', $1) #{extra}", [q])

    n
  end

  # The literal terms, OR-joined for websearch_to_tsquery. `or` is the one operator left for it to
  # read: a leading `-` (its NOT) and quotes (its phrases) are stripped, so a word is always searched for.
  defp any_terms(query), do: query |> tokens() |> Enum.join(" or ")

  defp tokens(query) do
    query
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&(&1 |> String.replace("\"", "") |> String.trim_leading("-")))
    |> Enum.reject(&(&1 == "" or String.downcase(&1) == "or"))
  end
end
