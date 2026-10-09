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

  Below the cosine line a model judges (`judged/5`): the turn-pass extractor labels its candidates,
  and `Server.Recall.Judge` asks about facts banked any other way. Its verdicts ship dark behind the
  `:judged_supersede` flag — off, each is an event `supersede_proposed` that a reviewer applies or
  rejects (`apply_proposal/1`, `reject_proposal/2`); on, it is applied and recorded `superseded`.
  Every judged verdict keeps its reason. Recall reads only the `supersedes` column, never these events.
  """
  import Ecto.Query

  alias Server.Event
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
    query = fact.thread_id |> in_scope() |> where([f], f.id < ^fact.id)
    query = if fact.provenance == "derived", do: where(query, [f], f.provenance == "derived"), else: query
    Repo.all(query)
  end

  @doc """
  The live, not-yet-superseded facts in `thread_id`'s scope: its project's, or the thread's own when
  it has no project. The pool every supersede — matched or judged — picks its older fact from.
  """
  @spec in_scope(pos_integer()) :: Ecto.Query.t()
  def in_scope(thread_id) do
    project = Repo.one(from t in Thread, where: t.id == ^thread_id, select: t.project_id)
    superseded = from f in Fact, where: not is_nil(f.supersedes), select: f.supersedes

    query =
      from f in Fact,
        join: t in Thread,
        on: t.id == f.thread_id,
        where: is_nil(f.forgotten_at) and f.id not in subquery(superseded)

    if project,
      do: where(query, [_f, t], t.project_id == ^project),
      else: where(query, [f], f.thread_id == ^thread_id)
  end

  @doc "The cosine at or above which a fact restates an older one outright (no model asked)."
  @spec threshold() :: float()
  def threshold, do: @threshold

  @doc """
  A model's verdict that `fact` restates or corrects the older fact `old_id`, with its one-line
  reason — from the turn-pass extractor (`how: "extracted"`) or the judge (`"judged"`,
  `Server.Recall.Judge`); the caller has checked the model was shown `old_id`.

  With the `:judged_supersede` flag off it is only proposed: event `supersede_proposed` on the fact's
  thread, correlation `"fact:<id>"`, detail `%{"old", "verdict", "reason", "how"}`, for a reviewer's
  `apply_proposal/1` or `reject_proposal/2`. With it on it is applied as `apply_proposal/1` would.
  A stated fact is never superseded: restating one does nothing, and correcting one asks the operator
  on the fact's thread instead. Returns the fact, updated when it now supersedes.
  """
  @spec judged(Fact.t(), pos_integer(), String.t(), String.t(), String.t()) :: Fact.t()
  def judged(%Fact{} = fact, old_id, verdict, reason, how) when verdict in ~w(restates corrects) do
    detail = %{"old" => old_id, "verdict" => verdict, "reason" => reason, "how" => how}

    if Server.Flags.enabled?(:judged_supersede) do
      case act(fact.id, detail) do
        {:ok, %Fact{} = updated} -> updated
        _ -> fact
      end
    else
      record("supersede_proposed", fact, detail)
      fact
    end
  end

  @doc """
  Apply the open `supersede_proposed` event `event_id`: the new fact supersedes the old one (event
  `superseded`, its detail the proposal's plus `"proposal"`), or — the old fact being stated and
  corrected — the operator is asked. Anything that stops it (a stated fact restated, a fact gone or
  already superseding) closes the proposal as rejected with that reason. `{:ok, fact}`, `{:ok, ask}`,
  or `{:error, :not_found | :resolved | reason}`.
  """
  @spec apply_proposal(integer()) :: {:ok, Fact.t() | Server.Message.t()} | {:error, term()}
  def apply_proposal(event_id) do
    with {:ok, proposal} <- open_proposal(event_id) do
      detail = Map.put(proposal.detail, "proposal", proposal.id)

      case act(fact_id(proposal), detail) do
        {:ok, %Fact{}} = applied ->
          applied

        {:ok, ask} ->
          close(proposal, "the old fact is stated: asked the operator (message #{ask.id})")
          {:ok, ask}

        {:error, why} ->
          close(proposal, "not applied: #{why}")
          {:error, why}
      end
    end
  end

  @doc """
  Reject the open `supersede_proposed` event `event_id` because of `reason`: event
  `supersede_rejected`, its detail the proposal's plus `"proposal"` and `"rejected"`. Nothing is
  superseded. `{:ok, event}` or `{:error, :not_found | :resolved}`.
  """
  @spec reject_proposal(integer(), String.t()) :: {:ok, Server.Event.t()} | {:error, term()}
  def reject_proposal(event_id, reason) when is_binary(reason) do
    with {:ok, proposal} <- open_proposal(event_id), do: close(proposal, reason)
  end

  defp close(proposal, reason) do
    detail = Map.merge(proposal.detail, %{"proposal" => proposal.id, "rejected" => reason})

    Server.Dossier.record_event(%{
      thread_id: proposal.thread_id,
      kind: "supersede_rejected",
      correlation: proposal.correlation,
      detail: detail
    })
  end

  defp open_proposal(event_id) do
    case Repo.get(Event, event_id) do
      %Event{kind: "supersede_proposed"} = proposal ->
        # The librarian's rule (Server.Librarian.proposals/1): any later event on the fact but a use,
        # a check or another proposal is a decision.
        decided =
          Repo.exists?(
            from e in Event,
              where:
                e.correlation == ^proposal.correlation and e.id > ^proposal.id and
                  e.kind not in ~w(cited check_passed check_failed supersede_proposed)
          )

        if decided, do: {:error, :resolved}, else: {:ok, proposal}

      _ ->
        {:error, :not_found}
    end
  end

  defp fact_id(%Event{correlation: "fact:" <> id}), do: String.to_integer(id)

  defp act(fact_id, %{"old" => old_id} = detail) do
    fact = Repo.get(Fact, fact_id)
    old = Repo.get(Fact, old_id)

    cond do
      is_nil(fact) or is_nil(old) or not is_nil(old.forgotten_at) -> {:error, :gone}
      old.provenance == "stated" and detail["verdict"] == "corrects" -> ask(fact, old, detail)
      old.provenance == "stated" -> {:error, :stated}
      not is_nil(fact.supersedes) -> {:error, :already_supersedes}
      true -> supersede_with(fact, old, detail)
    end
  end

  defp supersede_with(fact, old, detail) do
    fact = fact |> Ecto.Changeset.change(supersedes: old.id) |> Repo.update!()
    record("superseded", fact, detail)
    {:ok, fact}
  end

  defp ask(fact, old, detail) do
    Server.Attention.ask(
      fact.thread_id,
      "tlon",
      "fact ##{fact.id} (#{fact.provenance}) says your stated fact ##{old.id} is wrong — #{detail["reason"]}\n" <>
        "  stated: #{old.text}\n  now: #{fact.text}",
      ["the stated fact stands", "the new fact is right"]
    )
  end

  defp record(kind, fact, detail) do
    Server.Dossier.record_event(%{
      thread_id: fact.thread_id,
      kind: kind,
      correlation: "fact:#{fact.id}",
      detail: detail
    })
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
