defmodule Server.Recall.Supersede do
  @moduledoc """
  A fact that says what an older live fact in its scope already says supersedes it (`supersedes:
  old_id`), so recall's -3.0 `superseded` touch demotes the old copy instead of both staying equally
  strong. Run once the new fact's embedding is stored (`Server.Recall.store_embedding/3`), never on
  `bank_fact`'s path. "Says the same" is an exact match of the case/whitespace-folded text, else a
  cosine of at least 0.92. Scope is the fact's project (its thread when the thread has none); a
  thread-less seed fact neither supersedes nor is superseded. A `derived` fact never supersedes a
  `stated` one — the operator's words outrank our paraphrase of them. A fact that already names what
  it supersedes is left alone.
  """
  import Ecto.Query

  alias Server.Fact
  alias Server.Recall.Embedding
  alias Server.Repo
  alias Server.Thread

  # From the live store's pairwise cosines within a project: every pair at or above this restates one
  # claim; the first distinct pair (two different tickets with one blocker) scored 0.898.
  @threshold 0.92

  @doc """
  Point `fact` at the older live fact in its scope that it restates, if any. Returns the updated
  fact, or the fact unchanged when nothing matches.
  """
  @spec supersede(Fact.t()) :: Fact.t()
  def supersede(%Fact{supersedes: nil, thread_id: tid} = fact) when not is_nil(tid) do
    case match(fact, candidates(fact)) do
      nil -> fact
      old -> fact |> Ecto.Changeset.change(supersedes: old.id) |> Repo.update!()
    end
  end

  def supersede(%Fact{} = fact), do: fact

  @doc """
  What superseding the existing store would do: every live fact in id order, matched against the
  older live facts in its scope as if each earlier pairing had already landed. Returns
  `[{new_id, old_id, :exact | cosine}]`. Writes only with `write: true`; nothing runs it.
  """
  @spec backfill(keyword()) :: [{pos_integer(), pos_integer(), :exact | float()}]
  def backfill(opts \\ []) do
    facts =
      Repo.all(
        from f in Fact,
          join: t in Thread,
          on: t.id == f.thread_id,
          where: is_nil(f.forgotten_at),
          order_by: [asc: f.id],
          select: {f, t.project_id}
      )

    already = MapSet.new(Repo.all(from f in Fact, where: not is_nil(f.supersedes), select: f.supersedes))

    {pairs, _gone, _seen} = Enum.reduce(facts, {[], already, []}, &plan/2)
    pairs = Enum.reverse(pairs)

    if opts[:write] do
      for {new, old, _} <- pairs, do: Repo.update_all(from(f in Fact, where: f.id == ^new), set: [supersedes: old])
    end

    pairs
  end

  defp plan({fact, project}, {pairs, gone, seen}) do
    scope = if project, do: {:project, project}, else: {:thread, fact.thread_id}
    older = for {f, s} <- seen, s == scope, not MapSet.member?(gone, f.id), eligible?(fact, f), do: f
    pick = if is_nil(fact.supersedes), do: match(fact, older)

    case pick do
      nil -> {pairs, gone, [{fact, scope} | seen]}
      old -> {[{fact.id, old.id, how(fact, old)} | pairs], MapSet.put(gone, old.id), [{fact, scope} | seen]}
    end
  end

  defp candidates(%Fact{} = fact) do
    project = Repo.one(from t in Thread, where: t.id == ^fact.thread_id, select: t.project_id)
    superseded = from f in Fact, where: not is_nil(f.supersedes), select: f.supersedes

    query =
      from f in Fact,
        join: t in Thread,
        on: t.id == f.thread_id,
        where: f.id < ^fact.id and is_nil(f.forgotten_at) and f.id not in subquery(superseded)

    query =
      if project,
        do: where(query, [_f, t], t.project_id == ^project),
        else: where(query, [f], f.thread_id == ^fact.thread_id)

    query = if fact.provenance == "derived", do: where(query, [f], f.provenance == "derived"), else: query

    Repo.all(query)
  end

  defp eligible?(%Fact{provenance: "derived"}, %Fact{provenance: "stated"}), do: false
  defp eligible?(_new, _old), do: true

  # The newest exact restatement, else the closest embedding over the threshold.
  defp match(%Fact{} = fact, older) do
    text = fold(fact.text)

    Enum.find(Enum.sort_by(older, & &1.id, :desc), &(fold(&1.text) == text)) ||
      older
      |> Enum.filter(&(fact.embedding && &1.embedding))
      |> Enum.map(&{&1, Embedding.cosine(fact.embedding, &1.embedding)})
      |> Enum.filter(fn {_f, cos} -> cos >= @threshold end)
      |> Enum.max_by(fn {_f, cos} -> cos end, fn -> {nil, nil} end)
      |> elem(0)
  end

  defp how(fact, old) do
    if fold(fact.text) == fold(old.text),
      do: :exact,
      else: Float.round(Embedding.cosine(fact.embedding, old.embedding), 4)
  end

  defp fold(text), do: text |> String.downcase() |> String.split() |> Enum.join(" ")
end
