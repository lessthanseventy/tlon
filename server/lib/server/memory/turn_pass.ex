defmodule Server.Memory.TurnPass do
  @moduledoc """
  The post-response memory pass (worklines slice 5): when an agent's turn completes
  (`presence_idle`), a cheap extractor turns the turn's NEW messages into 0..3 banked
  facts — event-shaped and off the latency path, replacing turn-count nudges.

  One-brain piece E, slice 2: the pass is a job. `schedule/1` enqueues `Server.Jobs.TurnPass`
  for the thread (unique per thread for its interval — the old per-thread rate guard, now a
  row); `run/2` does one pass. Where the last pass stopped is `thread.memory_pass_last_id`, a
  column, so a restart never re-extracts a turn. Opt-in: `TLON_MEMORY_PASS=1` lets idles
  schedule; a dev shell never shells a model unasked.

  The extractor is shown the thread's facts and the live facts in its scope nearest the turn
  (`Server.Recall.Judge.nearest/3`), each by id, and labels each candidate `new`, or `restates` /
  `corrects` one of them with a reason — which goes to `Server.Recall.Supersede.judged/5` (how
  `"extracted"`), so the call that extracts also catches a correction cosine can't.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Jobs
  alias Server.Message
  alias Server.Recall
  alias Server.Recall.Judge
  alias Server.Recall.Supersede
  alias Server.Repo
  alias Server.Thread

  @defaults [
    extractor: Server.Memory.Extractor.Claude,
    min_messages: 3
  ]
  # A turn is a conversation beat, not an archive: the extractor sees at most this many.
  @window 20
  @max_facts 3

  @doc """
  Queue a pass for `thread_id` — a no-op unless the pass is on (`config :server, :memory_pass`)
  and Oban runs on this node. Never raises: an idle must not fail because memory is off.
  """
  def schedule(thread_id) when is_integer(thread_id) do
    if Application.get_env(:server, :memory_pass, false) do
      Jobs.enqueue(Jobs.TurnPass.new(%{thread_id: thread_id}))
    else
      {:error, :memory_pass_off}
    end
  end

  @doc "One pass over `thread_id`: extract from the messages since the last pass, bank, stamp."
  def run(thread_id, opts \\ []) do
    opts = Keyword.merge(@defaults, opts)

    with %Thread{} = thread <- Repo.get(Thread, thread_id),
         messages = new_messages(thread_id, thread.memory_pass_last_id || 0),
         true <- length(messages) >= opts[:min_messages] do
      # Stamp BEFORE extracting: an extractor fault must not re-run on the next idle.
      stamp(thread, messages)
      extract(thread, messages, opts)
    else
      _ -> :ok
    end
  end

  defp stamp(thread, messages) do
    last = messages |> List.last() |> Map.fetch!(:id)
    thread |> Ecto.Changeset.change(memory_pass_last_id: last) |> Repo.update()
  end

  defp extract(thread, messages, opts) do
    turn = Enum.map_join(messages, "\n", & &1.body)
    existing = Enum.uniq_by(Dossier.facts_for_thread(thread) ++ Judge.nearest(thread, turn, opts), & &1.id)
    shown = MapSet.new(existing, & &1.id)

    case opts[:extractor].extract(messages, existing) do
      {:ok, facts} ->
        facts |> Enum.take(@max_facts) |> Enum.each(&bank(thread.id, &1, List.last(messages).created_at, shown))

      {:error, _reason} ->
        :ok
    end

    :ok
  end

  defp bank(tid, %{kind: kind, text: text} = fact, observed_at, shown) do
    case Dossier.bank_fact(%{
           thread_id: tid,
           kind: kind,
           text: text,
           provenance: "derived",
           intent: Map.get(fact, :intent),
           observed_at: observed_at
         }) do
      {:ok, banked} -> banked |> label(fact, shown) |> Recall.embed_on_write(judge: false)
      {:error, _changeset} -> :ok
    end
  end

  # Only a fact the extractor was shown can be restated or corrected: an id it made up is dropped.
  defp label(banked, %{verdict: verdict, old: old} = fact, shown) when verdict in ~w(restates corrects) do
    if MapSet.member?(shown, old),
      do: Supersede.judged(banked, old, verdict, Map.get(fact, :reason) || "", "extracted"),
      else: banked
  end

  defp label(banked, _fact, _shown), do: banked

  # `tlon` writes process text (stage briefs, gate notices, nags), not conversation: extracting it
  # would bank the server's own playbook back into the dossier as fake decisions.
  defp new_messages(tid, last_id) do
    from(m in Message,
      where: m.thread_id == ^tid and m.id > ^last_id and m.author != "tlon",
      order_by: [desc: m.id],
      limit: @window
    )
    |> Repo.all()
    |> Enum.reverse()
  end
end
