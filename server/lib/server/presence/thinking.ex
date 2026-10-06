defmodule Server.Presence.Thinking do
  @moduledoc """
  The explicit half of "who is working": a harness DECLARES thinking at turn start
  and idle at turn end (via the `presence_thinking`/`presence_idle` MCP tools), so
  a surface can show "thinking" the moment a turn begins — no tmux-activity
  inference lag. The store is in memory — presence is liveness, not history; the
  harnesses re-declare on their next turn.

  Entries are `{thread_id, agent} => started_at`. A periodic sweep clears entries
  older than `:thinking_max_seconds` (default 600s) and announces them idle —
  the stuck-harness guard: a crashed harness that never sent `idle` must not read
  as thinking forever. Every transition broadcasts on `server:presence` and the
  thread topic (`Server.Bus`), and marks the agent's session (`Staff.mark_thinking/3`): the
  durable half, so a turn a machine restart cut off can be picked up (`Server.Staffing`).
  """
  use GenServer

  alias Server.Bus
  alias Server.Memory.TurnPass
  alias Server.Workline.Continuation

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

  @doc """
  Tag `agent`'s declared turn on `thread_id` with what it is doing now (`"edit"`, `"bash"`, …;
  `nil` = back to plain thinking). Leaves `started_at` alone. A no-op with no turn declared: a
  harness's fire-and-forget tool hook can land after the turn's idle, and must not reopen it.
  """
  def doing(store \\ __MODULE__, thread_id, agent, what), do: GenServer.call(store, {:doing, thread_id, agent, what})

  @doc "Who is thinking on `thread_id`: `[%{agent, started_at, doing}]`, empty when nobody."
  def thinking_for(store \\ __MODULE__, thread_id), do: GenServer.call(store, {:thinking_for, thread_id})

  @doc "Everyone thinking, keyed by thread id — a surface's reconcile-on-connect read."
  def thinking_all(store \\ __MODULE__), do: GenServer.call(store, :thinking_all)

  @doc "Run the stuck-harness sweep now (the timer calls this on its own interval)."
  def sweep(store \\ __MODULE__), do: GenServer.call(store, :sweep)

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_seconds, Application.get_env(:server, :thinking_max_seconds, @default_max_seconds))
    interval = Keyword.get(opts, :sweep_interval_ms, @sweep_interval_ms)
    Process.send_after(self(), :sweep, interval)
    {:ok, %{entries: %{}, doing: %{}, max_seconds: max, interval: interval}}
  end

  @impl true
  def handle_call({:thinking, thread_id, agent}, _from, state) do
    started_at = now()
    durable(thread_id, agent, started_at)
    Bus.broadcast({:presence_thinking, %{thread_id: thread_id, agent: agent, started_at: started_at}})
    {:reply, :ok, put_in(state.entries[{thread_id, agent}], started_at)}
  end

  def handle_call({:idle, thread_id, agent}, _from, state) do
    next = clear(state, thread_id, agent)
    # a DECLARED turn end, never the stuck sweep: only a harness that finished a turn is continued
    if next != state, do: _ = Continuation.schedule(thread_id)
    {:reply, :ok, next}
  end

  def handle_call({:doing, thread_id, agent, what}, _from, state) do
    key = {thread_id, agent}
    next = if Map.has_key?(state.entries, key), do: put_in(state.doing[key], what), else: state
    {:reply, :ok, next}
  end

  def handle_call({:thinking_for, thread_id}, _from, state) do
    entries =
      for {{^thread_id, agent} = key, started_at} <- state.entries do
        %{agent: agent, started_at: started_at, doing: state.doing[key]}
      end

    {:reply, entries, state}
  end

  def handle_call(:thinking_all, _from, state) do
    all =
      state.entries
      |> Enum.group_by(fn {{thread_id, _agent}, _at} -> thread_id end)
      |> Map.new(fn {thread_id, entries} ->
        {thread_id,
         Enum.map(entries, fn {{_tid, agent} = key, started_at} ->
           %{agent: agent, started_at: started_at, doing: state.doing[key]}
         end)}
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
        durable(thread_id, agent, nil)

        # the turn ended: queue its memory pass (a no-op unless the pass is on and Oban runs here)
        _ = TurnPass.schedule(thread_id)
        %{state | entries: entries, doing: Map.delete(state.doing, {thread_id, agent})}
    end
  end

  # the session row's mark (Staff.mark_thinking): best-effort, presence never fails on the db
  defp durable(thread_id, agent, at) do
    Server.Staff.mark_thinking(thread_id, agent, at)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
