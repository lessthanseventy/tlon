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

  Beside it, each thread's ACTIVITY feed: the last 100 things its coworkers did
  (`%{thread_id, agent, at, kind, summary}`, oldest first) — a tool call as the harness's hook
  reported it (`presence_doing` with a `summary`: "Bash · mise run check"), a post, and a
  `thinking` mark when a turn starts after a pause (`:turn_gap_seconds`, default 30s, so a
  harness that declares a turn per model step does not mark every step). A summary is one line,
  capped and redacted (`record/5`), never file contents. The office's thread card reads it
  (`Server.Office.thread_view/2`). In memory like the rest: a restart starts the feeds empty.
  """
  use GenServer

  alias Server.Bus
  alias Server.Memory.TurnPass
  alias Server.Workline.Continuation

  @default_max_seconds 600
  @sweep_interval_ms 60_000
  @activity_cap 100
  @default_turn_gap_seconds 30
  @summary_max 120
  # a credential in a command line: an auth header's value, a NAME_KEY=/token= assignment, a
  # well-known token prefix, or a long opaque run
  @secrets [
    {~r/(bearer|basic|token)\s+\S+/i, "\\1 …"},
    {~r/\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*|token|key|secret|password|passwd|api[_-]?key)=\S+/i,
     "\\1=…"},
    {~r/\b(?:sk|pk|rk|ghp|gho|ghs|ghu|github_pat|glpat|xox[abpr]|AKIA)[-_][A-Za-z0-9_\-]{8,}/, "…"},
    {~r/[A-Za-z0-9+_\-]{40,}/, "…"}
  ]

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

  @doc """
  Add to `thread_id`'s activity feed: `agent` did a `kind` of thing (`nil` = a tool the server has
  no kind for, read as `"tool"`), said in one line. The summary is cut to its first line and
  #{@summary_max} characters, with anything that looks like a credential redacted.
  """
  def record(store \\ __MODULE__, thread_id, agent, kind, summary) when is_binary(summary),
    do: GenServer.call(store, {:record, thread_id, agent, kind || "tool", clean(summary)})

  @doc "`thread_id`'s activity feed, oldest first: `[%{thread_id, agent, at, kind, summary}]`."
  def activity(store \\ __MODULE__, thread_id), do: GenServer.call(store, {:activity, thread_id})

  @doc "How many events a thread's feed keeps."
  def activity_cap, do: @activity_cap

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
    gap = Keyword.get(opts, :turn_gap_seconds, @default_turn_gap_seconds)
    Process.send_after(self(), :sweep, interval)

    {:ok, %{entries: %{}, doing: %{}, activity: %{}, idled: %{}, max_seconds: max, interval: interval, turn_gap: gap}}
  end

  @impl true
  def handle_call({:thinking, thread_id, agent}, _from, state) do
    started_at = now()
    key = {thread_id, agent}
    durable(thread_id, agent, started_at)
    Bus.broadcast({:presence_thinking, %{thread_id: thread_id, agent: agent, started_at: started_at}})

    fresh? =
      not Map.has_key?(state.entries, key) and
        case state.idled[key] do
          nil -> true
          at -> DateTime.diff(started_at, at, :second) >= state.turn_gap
        end

    state = if fresh?, do: push(state, thread_id, agent, "thinking", "thinking"), else: state
    {:reply, :ok, put_in(state.entries[key], started_at)}
  end

  def handle_call({:record, thread_id, agent, kind, summary}, _from, state),
    do: {:reply, :ok, push(state, thread_id, agent, kind, summary)}

  def handle_call({:activity, thread_id}, _from, state), do: {:reply, Map.get(state.activity, thread_id, []), state}

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

        %{
          state
          | entries: entries,
            doing: Map.delete(state.doing, {thread_id, agent}),
            idled: Map.put(state.idled, {thread_id, agent}, now())
        }
    end
  end

  defp push(state, thread_id, agent, kind, summary) do
    event = %{thread_id: thread_id, agent: agent, at: now(), kind: kind, summary: summary}
    feed = Map.get(state.activity, thread_id, []) ++ [event]
    %{state | activity: Map.put(state.activity, thread_id, Enum.take(feed, -@activity_cap))}
  end

  defp clean(summary) do
    line = summary |> String.split("\n", parts: 2) |> hd() |> String.trim()
    line = Enum.reduce(@secrets, line, fn {re, with}, acc -> Regex.replace(re, acc, with) end)
    if String.length(line) > @summary_max, do: String.slice(line, 0, @summary_max - 1) <> "…", else: line
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
