defmodule Server.Recall.Judge do
  @moduledoc """
  The cheap model's call on a fact that cosine alone can't settle: one RELATED to older live facts in
  its scope (cosine in `[0.78, Supersede.threshold/0)` — under the duplicate line, where a newer
  fact may correct an older one in other words) is asked whether it is `new`, `restates <id>` or
  `corrects <id>`, with a one-line reason; a restatement or correction goes to
  `Server.Recall.Supersede.judged/5` (how `"judged"`), which proposes or applies it under the
  `:judged_supersede` flag. Runs off the write path once a fact's embedding is stored
  (`Server.Recall.embed_on_write/2`), for facts banked any way but the turn pass — whose extractor
  labels its own candidates against `nearest/3`'s facts in the same call.

  The model is configuration (`config :server, supersede_judge_cmd:, supersede_judge_model:`,
  default `pi` on the flat ollama bucket); a model that is down, slow or unparseable changes nothing.
  """
  import Ecto.Query

  alias Server.Fact
  alias Server.Recall.Embedding
  alias Server.Recall.Supersede
  alias Server.Repo

  # From the live store's within-project pairwise cosines: a fact and the behaviour its fix replaced sat
  # at 0.794; at 0.78, 219 of ~730 live facts have a band neighbour (342 pairs at @max a fact).
  @floor 0.78
  @max 3
  @nearest 5
  @timeout_s 30

  @contract """
  You keep a project's memory honest. Compare the NEW fact with each OLDER fact and answer ONE of:
  - "restates": the NEW fact says EVERYTHING an older fact says (it may say more), so the older copy
    adds nothing. If the older fact has any detail the NEW one lacks — a remedy, a reason, a general
    rule the NEW fact is one case of — it is not a restatement: answer "new".
  - "corrects": the NEW fact and an older fact cannot both be true now (the behaviour it describes
    was changed, a decision was reversed, a value or an owner changed), so the older fact should stop
    being trusted. Two facts that use different numbers for one thing are not a contradiction.
  - "new": anything else — it adds detail, is about a different thing, or both stay true together
    (a history of what happened before a fix, a cause and its fix, two halves of one design).
  When unsure, answer "new". Respond with ONLY a JSON object:
  {"verdict": "new"|"restates"|"corrects", "id": <the older fact's number, or null>, "reason": "<one line>"}
  """

  @doc """
  Judge `fact` against its related older facts. Returns the fact, updated when it now supersedes.
  `:model` replaces the model call (`prompt -> {:ok, text} | {:error, _}`), a test seam.
  """
  @spec judge(Fact.t(), keyword()) :: Fact.t()
  def judge(fact, opts \\ [])

  def judge(%Fact{supersedes: nil, thread_id: tid, embedding: [_ | _]} = fact, opts) when not is_nil(tid) do
    with [_ | _] = near <- related(fact),
         {:ok, out} <- model(opts).(prompt(fact, near)),
         {verdict, old, reason} <- parse(out, Enum.map(near, & &1.id)) do
      Supersede.judged(fact, old, verdict, reason, "judged")
    else
      _ -> fact
    end
  end

  def judge(%Fact{} = fact, _opts), do: fact

  @doc """
  The older live facts in `fact`'s scope whose cosine to it is in the judge's band, closest first,
  at most #{@max}.
  """
  @spec related(Fact.t()) :: [Fact.t()]
  def related(%Fact{} = fact) do
    fact.thread_id
    |> Supersede.in_scope()
    |> where([f], f.id < ^fact.id and not is_nil(f.embedding))
    |> Repo.all()
    |> Enum.map(&{&1, Embedding.cosine(fact.embedding, &1.embedding)})
    |> Enum.filter(fn {_f, cos} -> cos >= @floor and cos < Supersede.threshold() end)
    |> Enum.sort_by(fn {_f, cos} -> cos end, :desc)
    |> Enum.take(@max)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  The live facts in `thread`'s scope nearest to `text`, at most #{@nearest}: by embedding when the
  embedder answers within 2s, else by keyword (`text_tsv`) — never blocking on a down embedder. What
  the turn-pass extractor labels its candidates against. `:embed` replaces the embedder (a test seam).
  """
  @spec nearest(Server.Thread.t(), String.t(), keyword()) :: [Fact.t()]
  def nearest(thread, text, opts \\ []) do
    pool = Repo.all(Supersede.in_scope(thread.id))
    embed = opts[:embed] || (&Embedding.embed(&1, timeout: 2_000))

    scores =
      case embed.(text) do
        {:ok, vector} -> for f <- pool, f.embedding, into: %{}, do: {f.id, Embedding.cosine(vector, f.embedding)}
        {:error, _} -> Server.Search.fact_relevance(text, Enum.map(pool, & &1.id))
      end

    pool
    |> Enum.filter(&Map.has_key?(scores, &1.id))
    |> Enum.sort_by(&scores[&1.id], :desc)
    |> Enum.take(@nearest)
  end

  @doc "The judge's prompt: the contract, the older facts by id, the new fact."
  @spec prompt(Fact.t(), [Fact.t()]) :: String.t()
  def prompt(fact, near) do
    @contract <>
      "\nOLDER FACTS:\n" <>
      Enum.map_join(near, "\n", &"##{&1.id}: #{&1.text}") <> "\n\nNEW FACT:\n##{fact.id}: #{fact.text}\n"
  end

  @doc """
  `{verdict, old_id, reason}` for a restatement or correction of one of `ids`; `:new` for "new"; nil
  when the reply doesn't parse or names a fact it wasn't shown.
  """
  @spec parse(String.t(), [pos_integer()]) :: {String.t(), pos_integer(), String.t()} | :new | nil
  def parse(out, ids), do: Server.JsonBlob.first_valid(out, &shape(&1, ids))

  defp shape(%{"verdict" => "new"}, _ids), do: :new

  defp shape(%{"verdict" => verdict, "id" => id} = reply, ids) when verdict in ~w(restates corrects) do
    id = to_id(id)
    if id in ids, do: {verdict, id, to_string(reply["reason"] || "")}
  end

  defp shape(_reply, _ids), do: nil

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(String.trim_leading(id, "#")) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_id(_id), do: nil

  defp model(opts) do
    opts[:model] ||
      fn prompt ->
        Server.ModelCli.prompt(
          prompt,
          :supersede_judge_cmd,
          :supersede_judge_model,
          {"pi", "ollama-cloud/deepseek-v4.1-flash"},
          timeout_s: @timeout_s
        )
      end
  end
end
