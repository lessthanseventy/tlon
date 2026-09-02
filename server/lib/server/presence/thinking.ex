defmodule Server.Presence.Thinking do
  @moduledoc """
  The explicit half of "who is working": a harness DECLARES thinking at turn start
  and idle at turn end (via the `presence_thinking`/`presence_idle` MCP tools), so
  a cockpit can show "thinking" the moment a turn begins — no tmux-activity
  inference lag. In-memory only: presence is liveness, not history, so a restart
  losing it is correct (the harnesses re-declare on their next turn).

  Entries are `{thread_id, agent} => started_at`. A periodic sweep clears entries
  older than `:thinking_max_seconds` (default 600s) and announces them idle —
  the stuck-harness guard: a crashed harness that never sent `idle` must not read
  as thinking forever. Every transition broadcasts on `server:presence` and the
  thread topic (`Server.Bus`).
  """
  use GenServer

  alias Server.Bus

  @default_max_seconds 600
  @sweep_interval_ms 60_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Declare `agent` thinking on `thread_id` (idempotent — a re-declare refreshes `started_at`)."
  def thinking(store \\ __MODULE__, thread_id, agent), do: GenServer.call(store, {:thinking, thread_id, agent})

  @doc "Declare `agent` done thinking on `thread_id`. A no-op for an agent that never declared."
  def idle(store \\ __MODULE__, thread_id, agent), do: GenServer.call(store, {:idle, thread_id, agent})

  @doc "Who is thinking on `thread_id`: `[%{agent, started_at}]`, empty when nobody."
  def thinking_for(store \\ __MODULE__, thread_id), do: GenServer.call(store, {:thinking_for, thread_id})

  @doc "Everyone thinking, keyed by thread id — the cockpit's reconcile-on-connect read."
  def thinking_all(store \\ __MODULE__), do: GenServer.call(store, :thinking_all)

  @doc "Run the stuck-harness sweep now (the timer calls this on its own interval)."
  def sweep(store \\ __MODULE__), do: GenServer.call(store, :sweep)

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_seconds, Application.get_env(:server, :thinking_max_seconds, @default_max_seconds))
    interval = Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms)
    Process.send_after(self(), :sweep, interval)
    {:ok, %{entries: %{}, max_seconds: max, interval: interval}}
  end

  @impl true
  def handle_call({:thinking, thread_id, agent}, _from, state) do
    started_at = now()
    Bus.broadcast({:presence_thinking, %{thread_id: thread_id, agent: agent, started_at: started_at}})
    {:reply, :ok, put_in(state.entries[{thread_id, agent}], started_at)}
  end

  def handle_call({:idle, thread_id, agent}, _from, state) do
    {:reply, :ok, clear(state, thread_id, agent)}
  end

  def handle_call({:thinking_for, thread_id}, _from, state) do
    entries =
      for {{^thread_id, agent}, started_at} <- state.entries do
        %{agent: agent, started_at: started_at}
      end

    {:reply, entries, state}
  end

  def handle_call(:thinking_all, _from, state) do
    all =
      state.entries
      |> Enum.group_by(fn {{thread_id, _agent}, _at} -> thread_id end)
      |> Map.new(fn {thread_id, entries} ->
        {thread_id, Enum.map(entries, fn {{_tid, agent}, started_at} -> %{agent: agent, started_at: started_at} end)}
      end)

    {:reply, all, state}
  end

  def handle_call(:sweep, _from, state), do: {:reply, :ok, do_sweep(state)}

  @impl true
  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, state.interval)
    {:noreply, do_sweep(state)}
  end

  defp do_sweep(state) do
    cutoff = now()

    state.entries
    |> Enum.filter(fn {_key, started_at} -> DateTime.diff(cutoff, started_at, :second) >= state.max_seconds end)
    |> Enum.reduce(state, fn {{thread_id, agent}, _at}, acc -> clear(acc, thread_id, agent) end)
  end

  # Broadcast idle only on a real removal — a no-op idle stays silent.
  defp clear(state, thread_id, agent) do
    case Map.pop(state.entries, {thread_id, agent}) do
      {nil, _entries} ->
        state

      {_started_at, entries} ->
        Bus.broadcast({:presence_idle, %{thread_id: thread_id, agent: agent}})
        %{state | entries: entries}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
