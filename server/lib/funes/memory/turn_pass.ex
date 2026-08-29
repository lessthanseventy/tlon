defmodule Server.Memory.TurnPass do
  @moduledoc """
  The post-response memory pass (worklines slice 5): when an agent's turn completes
  (`presence_idle`), a cheap extractor turns the turn's NEW messages into 0..3 banked
  facts — event-shaped and off the latency path, replacing turn-count nudges. Guards:
  at least `min_messages` new messages since the last pass on that thread, and at most
  one pass per `min_interval_ms` per thread. Opt-in: `TLON_MEMORY_PASS=1` starts it
  under the application; tests drive an unsubscribed instance directly.
  """

  use GenServer

  import Ecto.Query

  alias Server.Dossier
  alias Server.Message
  alias Server.Recall
  alias Server.Repo
  alias Server.Thread

  @defaults [
    extractor: Server.Memory.Extractor.Claude,
    min_messages: 3,
    min_interval_ms: to_timeout(minute: 10),
    subscribe: true
  ]
  # A turn is a conversation beat, not an archive: the extractor sees at most this many.
  @window 20
  @max_facts 3

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    if name, do: GenServer.start_link(__MODULE__, opts, name: name), else: GenServer.start_link(__MODULE__, opts)
  end

  @doc "Synchronize with the pass — returns after every queued idle has been handled (tests)."
  def drain(server), do: GenServer.call(server, :drain)

  @impl true
  def init(opts) do
    opts = Keyword.merge(@defaults, opts)
    if opts[:subscribe], do: Server.Bus.subscribe_presence()
    {:ok, %{opts: opts, seen: %{}}}
  end

  @impl true
  def handle_call(:drain, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:presence_idle, %{thread_id: tid}}, state) when is_integer(tid),
    do: {:noreply, maybe_extract(tid, state)}

  def handle_info(_event, state), do: {:noreply, state}

  defp maybe_extract(tid, %{opts: opts, seen: seen} = state) do
    %{last_id: last_id, at: at} = Map.get(seen, tid, %{last_id: 0, at: 0})
    now = System.monotonic_time(:millisecond)
    messages = new_messages(tid, last_id)

    cond do
      at != 0 and now - at < opts[:min_interval_ms] -> state
      length(messages) < opts[:min_messages] -> state
      true -> extract(tid, messages, %{state | seen: stamp(seen, tid, messages, now)})
    end
  end

  # Stamp BEFORE extracting: an extractor fault must not hot-loop on every idle.
  defp stamp(seen, tid, messages, now),
    do: Map.put(seen, tid, %{last_id: messages |> List.last() |> Map.fetch!(:id), at: now})

  defp extract(tid, messages, %{opts: opts} = state) do
    existing = Dossier.facts_for_thread(%Thread{id: tid})

    case opts[:extractor].extract(messages, existing) do
      {:ok, facts} -> facts |> Enum.take(@max_facts) |> Enum.each(&bank(tid, &1))
      {:error, _reason} -> :ok
    end

    state
  end

  defp bank(tid, %{kind: kind, text: text} = fact) do
    case Dossier.bank_fact(%{
           thread_id: tid,
           kind: kind,
           text: text,
           provenance: "derived",
           intent: Map.get(fact, :intent)
         }) do
      {:ok, banked} -> Recall.embed_on_write(banked)
      {:error, _changeset} -> :ok
    end
  end

  # Machine-authored process text (stage briefs, gate notices, nags) is NOT conversation:
  # extracting it would bank server' own playbook back into the dossier as fake decisions.
  @machine_authors ~w(tlon console)

  defp new_messages(tid, last_id) do
    from(m in Message,
      where: m.thread_id == ^tid and m.id > ^last_id and m.author not in ^@machine_authors,
      order_by: [desc: m.id],
      limit: @window
    )
    |> Repo.all()
    |> Enum.reverse()
  end
end
