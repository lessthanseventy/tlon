defmodule Server.Recall do
  @moduledoc """
  The forgetting engine's recall layer (design:
  `docs/plans/2026-08-19-funes-forgetting-design.md`): assemble the WORKING SET — the
  token-budgeted slice of memory that reaches an agent's context. Candidates are ranked by
  `relevance × strength` (`Server.Recall.Strength`); the operator's pinned constraints are a floor
  that is always kept; the ranked remainder fills the remaining token budget and everything else
  falls out of context — never off disk (an explicit deeper search still finds it). `assemble/2`
  is the pure core; DB-backed gatherers feed it real candidates.
  """
  import Ecto.Query

  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Recall.Embedding
  alias Server.Recall.Strength
  alias Server.Repo
  alias Server.Thread

  # Fact-correlated events that count as strength touches (weighted in Server.Recall.Strength).
  @touch_kinds ["check_passed", "check_failed", "cited"]
  @default_budget 4000
  # A brief must not wait on ollama: the query embedding is a hint, and a down embedder degrades
  # to keyword relevance within this bound. Writes (`embed_fact/1`) keep the embedder's default.
  @query_embed_timeout_ms 1_000
  # An unrelated fact is never scored to zero — the query is a hint that lifts what it names, and
  # strength still orders everything else (a fact must be 5× stronger to beat a query hit).
  @relevance_floor 0.2

  @type candidate :: %{
          optional(any()) => any(),
          relevance: number(),
          strength: number(),
          tokens: pos_integer(),
          pinned?: boolean()
        }

  @doc """
  Assemble the working set from scored candidates. Pinned candidates are kept unconditionally and
  first; non-pinned candidates with positive strength are ranked by `relevance × strength` and
  added while they fit the remaining `:budget` (tokens). Everything else is dropped from context.
  """
  @spec assemble([candidate()], keyword()) :: [candidate()]
  def assemble(candidates, opts) do
    budget = Keyword.fetch!(opts, :budget)
    {pinned, rest} = Enum.split_with(candidates, & &1.pinned?)

    pinned = Enum.sort_by(pinned, &score/1, :desc)
    remaining = max(budget - Enum.sum(Enum.map(pinned, & &1.tokens)), 0)

    ranked =
      rest
      |> Enum.filter(&(&1.strength > 0))
      |> Enum.sort_by(&score/1, :desc)
      |> fill(remaining)

    pinned ++ ranked
  end

  # Rank = relevance × strength. A dead (non-positive strength) fact scores at or below zero and
  # is dropped upstream; among the living, more-relevant-and-stronger wins.
  defp score(%{relevance: r, strength: s}), do: r * s

  # Greedily keep candidates whose tokens fit the running budget — skipping an over-budget fact so
  # a smaller lower-ranked one can still land, rather than stopping at the first that doesn't fit.
  defp fill(candidates, budget) do
    {kept, _left} =
      Enum.reduce(candidates, {[], budget}, fn c, {kept, left} ->
        if c.tokens <= left, do: {[c | kept], left - c.tokens}, else: {kept, left}
      end)

    Enum.reverse(kept)
  end

  @doc """
  Assemble a thread's working set from the DB: the pinned operator constraints plus the thread's
  facts, each scored by strength (from its touch events) × relevance to `:query` (keyword bm25
  soft-OR'd with cosine over `:query_embedding`/an ollama embedding of the query; uniform with no
  query), cut to the token budget. `Server.Board.brief/1` derives the query from the thread's title
  and the operator's latest message.
  """
  @spec working_set_for_thread(Thread.t(), keyword()) :: [candidate()]
  def working_set_for_thread(%Thread{} = thread, opts \\ []) do
    now = opts[:now] || DateTime.utc_now()
    budget = opts[:budget] || recall_budget()
    query_vec = query_vector(opts)

    constraints = Dossier.always_loaded_constraints()
    pinned_ids = MapSet.new(constraints, & &1.id)
    thread_facts = Dossier.facts_for_thread(thread)

    # `:include_pinned` (default true) prepends the GLOBAL operator-constraint set — the session-
    # start "pinned + thread facts" working set. A thread's LEARNINGS pane passes false: it ranks the
    # thread's OWN facts only (a thread's own stated constraints are still pinned via `pinned_ids`),
    # so one thread's dossier never shows another thread's constraints.
    facts =
      if Keyword.get(opts, :include_pinned, true),
        do: Enum.uniq_by(constraints ++ thread_facts, & &1.id),
        else: thread_facts

    ids = Enum.map(facts, & &1.id)
    keyword = keyword_relevance(opts[:query], ids)
    touch_events = touches_by_fact(ids)
    superseded = superseded_ids(ids)

    facts
    |> Enum.map(fn f ->
      touches =
        Strength.touches_for(
          %{
            created_at: f.created_at,
            touches: Map.get(touch_events, f.id, []),
            superseded?: MapSet.member?(superseded, f.id)
          },
          now
        )

      %{
        id: f.id,
        fact: f,
        relevance: relevance(f, query_vec, keyword),
        strength: Strength.of(touches, now),
        tokens: est_tokens(f.text),
        pinned?: MapSet.member?(pinned_ids, f.id)
      }
    end)
    |> assemble(budget: budget)
  end

  @doc """
  A thread's LEARNINGS as the recall read path serves them: the thread's own facts from the working
  set (ranked by relevance × strength, cut to the token budget), shaped `%{shown, more}` like every
  capped brief pane. Thread-scoped — the global pinned set is NOT folded in (that is the
  always-loaded resource's job), but a thread's own stated constraints stay pinned and present.
  `more` counts what fell out of the budget (never off disk — `get_facts` still returns the total),
  never a silent cut.
  """
  @spec thread_learnings(Thread.t(), keyword()) :: %{shown: [Fact.t()], more: non_neg_integer()}
  def thread_learnings(%Thread{} = thread, opts \\ []) do
    shown =
      thread
      |> working_set_for_thread(Keyword.put(opts, :include_pinned, false))
      |> Enum.map(& &1.fact)

    total = length(Dossier.facts_for_thread(thread))
    %{shown: shown, more: max(total - length(shown), 0)}
  end

  # The query's embedding: a precomputed `:query_embedding` (the test/cached path), else embed the
  # `:query` string via ollama, else nil (a session-start recall with no query → uniform relevance).
  defp query_vector(opts) do
    cond do
      vec = opts[:query_embedding] ->
        vec

      q = opts[:query] ->
        case Embedding.embed(q, model: embedding_model(), timeout: @query_embed_timeout_ms) do
          {:ok, vec} -> vec
          {:error, _} -> nil
        end

      true ->
        nil
    end
  end

  # Relevance blends the semantic (cosine) and keyword (bm25) signals as a soft-OR — a fact matching
  # EITHER strongly is relevant, both is best, capped at 1 — lifted onto the floor. No query at all
  # → uniform 1.0 (rank by pure strength); the best keyword hit is fully relevant with no embedding.
  defp relevance(_fact, nil, nil), do: 1.0

  defp relevance(fact, query_vec, keyword) do
    s = semantic_rel(fact, query_vec)
    k = keyword_rel(fact, keyword)
    @relevance_floor + (1 - @relevance_floor) * (s + k - s * k)
  end

  defp semantic_rel(_fact, nil), do: 0.0
  defp semantic_rel(%{embedding: nil}, _query_vec), do: 0.0
  defp semantic_rel(%{embedding: emb}, query_vec), do: max(Embedding.cosine(query_vec, emb), 0.0)

  defp keyword_rel(_fact, nil), do: 0.0
  defp keyword_rel(%{id: id}, keyword), do: Map.get(keyword, id, 0.0)

  # The keyword half: each candidate's bm25 relevance to the query, or nil when there's no query.
  defp keyword_relevance(nil, _ids), do: nil
  defp keyword_relevance(query, ids), do: Server.Search.fact_relevance(query, ids)

  @doc "Store a fact's embedding vector + model (written after `bank_fact`, off the write path)."
  @spec store_embedding(Fact.t(), [float()], String.t()) :: {:ok, Fact.t()} | {:error, term()}
  def store_embedding(%Fact{} = fact, vector, model) do
    fact |> Fact.embedding_changeset(vector, model) |> Repo.update()
  end

  @doc """
  Best-effort: embed a fact's text with the configured model and store the vector. A down embedder
  is a no-op (`{:error, _}`, recall falls back to keyword) — it never blocks or fails the caller.
  """
  @spec embed_fact(Fact.t()) :: {:ok, Fact.t()} | {:error, term()}
  def embed_fact(%Fact{} = fact) do
    model = embedding_model()

    case Embedding.embed(fact.text, model: model) do
      {:ok, vector} -> store_embedding(fact, vector, model)
      {:error, reason} -> {:error, reason}
    end
  rescue
    # The write is best-effort and runs async off the request path — a fact deleted mid-flight
    # (a stale-entry update), a down Repo, anything: swallow it. An embedding is never load-bearing.
    e -> {:error, e}
  end

  @doc """
  Embed a freshly-banked fact OFF the write path: a supervised, unlinked task hits ollama so a
  slow/down embedder never blocks the `bank_fact` reply, and its crash can't take the caller. Called
  from the MCP write path (`Server.MCP.Tool.BankFact`); returns the fact unchanged (a side effect on
  the write result, never load-bearing). A node with no embedder just no-ops (`embed_fact` is
  best-effort — recall falls back to keyword + strength).
  """
  @spec embed_on_write(Fact.t()) :: Fact.t()
  def embed_on_write(%Fact{} = fact) do
    Task.Supervisor.start_child(Server.TaskSupervisor, fn -> embed_fact(fact) end)
    fact
  end

  defp embedding_model, do: get_in(Application.get_env(:server, :embedding, []), [:model]) || "nomic-embed-text"

  @doc """
  The recall corpus at a glance — the observability read behind console's Memory pane: total facts,
  how many carry an embedding (semantic-recall coverage), and the always-loaded floor's size in
  facts and estimated tokens against the working-set budget. Cheap: two counts + the floor query.
  """
  @spec coverage() :: %{
          facts: non_neg_integer(),
          embedded: non_neg_integer(),
          pinned_count: non_neg_integer(),
          pinned_tokens: non_neg_integer(),
          budget: pos_integer(),
          model: String.t()
        }
  def coverage(workspace_id \\ nil) do
    pinned = Dossier.always_loaded_constraints(workspace_id)
    facts = Fact.in_workspace(Fact, workspace_id)

    %{
      facts: Repo.aggregate(facts, :count),
      embedded: Repo.aggregate(from(f in facts, where: not is_nil(f.embedding)), :count),
      pinned_count: length(pinned),
      pinned_tokens: pinned |> Enum.map(&est_tokens(&1.text)) |> Enum.sum(),
      budget: recall_budget(),
      model: embedding_model()
    }
  end

  defp recall_budget, do: get_in(Application.get_env(:server, :recall, []), [:budget]) || @default_budget

  # ~4 chars per token — a rough estimate, enough to bound the working set by tokens (design: a
  # budget, not a row count). A precise tokenizer can replace this without changing the seam.
  defp est_tokens(text), do: max(div(String.length(text || ""), 4), 1)

  # Each fact's touch events (rechecks + citations), grouped by fact id — correlation `"fact:<id>"`.
  defp touches_by_fact([]), do: %{}

  defp touches_by_fact(fact_ids) do
    correlations = Enum.map(fact_ids, &"fact:#{&1}")

    from(e in Event,
      where: e.correlation in ^correlations and e.kind in ^@touch_kinds,
      select: {e.correlation, e.kind, e.created_at}
    )
    |> Repo.all()
    |> Enum.group_by(fn {corr, _kind, _at} -> fact_id_of(corr) end, fn {_corr, kind, at} -> %{kind: kind, at: at} end)
  end

  defp fact_id_of("fact:" <> id), do: String.to_integer(id)

  # The set of fact ids that a later fact supersedes — a hard-negative touch.
  defp superseded_ids([]), do: MapSet.new()

  defp superseded_ids(fact_ids) do
    from(f in Fact, where: not is_nil(f.supersedes) and f.supersedes in ^fact_ids, select: f.supersedes)
    |> Repo.all()
    |> MapSet.new()
  end
end
