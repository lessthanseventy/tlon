defmodule Server.Jobs.Passes do
  @moduledoc """
  How long the per-tick passes (`Drain`, `Staff`, `Dispatch`, `KeepUp`) take, read off the rows Oban
  stamps on every run: the same span its `[:oban, :job, :stop]` telemetry reports, kept 7 days by the
  pruner, readable from `server:doctor` without a running node. `Staff` has concurrency 1 and a
  300 s unique period, so a pass that overruns its minute silently skips ticks: `slow/0` names the
  ones whose newest pass took over 30 s (or is running past 30 s now), and the box's Needs raise
  `health:job_slow` for them, reading `slow_cached/0`.

  `Maintain` is not here: it runs every half hour and takes 18-52 s by design.
  """
  import Ecto.Query

  alias Server.Repo

  @workers ~w(Drain Staff Dispatch KeepUp)
  @slow_ms 30_000
  @news_s 900
  @cache_ms 30_000

  @doc "Each pass worker's last `n` durations in ms, newest first: `[{\"Staff\", [41_000, 2_000]}]`; only workers that have run."
  def recent(n \\ 3) do
    rows = Repo.all(durations(from(j in Oban.Job, order_by: [desc: j.completed_at])))

    for short <- @workers,
        ms = Enum.take(for({worker, d} <- rows, worker == "Server.Jobs." <> short, do: d), n),
        ms != [],
        do: {short, ms}
  end

  @doc """
  The workers whose newest pass, finished in the last 15 minutes, took over 30 s, or that are
  executing now and have been for over 30 s (the span so far): `[{"Staff", 41_000}]`. A running pass
  counts at once, so the alarm does not wait for the damage to finish.
  """
  def slow do
    now = DateTime.utc_now()
    since = DateTime.add(now, -@news_s)

    newest =
      Repo.all(
        durations(
          from(j in Oban.Job,
            where: j.completed_at > ^since,
            distinct: j.worker,
            order_by: [asc: j.worker, desc: j.completed_at]
          )
        )
      )

    names = Enum.map(@workers, &"Server.Jobs.#{&1}")

    running =
      from(j in Oban.Job,
        where: j.worker in ^names and j.state == "executing" and not is_nil(j.attempted_at),
        select: {j.worker, j.attempted_at}
      )
      |> Repo.all()
      |> Enum.map(fn {w, at} -> {w, DateTime.diff(now, at, :millisecond)} end)

    for {"Server.Jobs." <> short, ms} <- slowest(newest ++ running), ms > @slow_ms, do: {short, ms}
  end

  @doc """
  `slow/0`, read at most every 30 s: `Server.Office.Needs` asks on every list, and the query scans
  `oban_jobs` (about a week of per-minute crons, no index on `completed_at`). A `:persistent_term`
  holds the reading; it is rewritten only when stale, so the global GC a changed term costs is paid
  twice a minute at most, and the alarm lags a pass by at most 30 s.
  """
  def slow_cached(now \\ System.monotonic_time(:millisecond)) do
    case :persistent_term.get({__MODULE__, :slow}, nil) do
      {at, slow} when now - at < @cache_ms ->
        slow

      _ ->
        slow = slow()
        :persistent_term.put({__MODULE__, :slow}, {now, slow})
        slow
    end
  end

  @doc false
  def forget, do: :persistent_term.erase({__MODULE__, :slow})

  @doc "One line for `server:doctor`: `Drain 0.1s 0.1s; Staff 1.2s ...`, or `none` when no pass has run."
  def line do
    case recent() do
      [] -> "none"
      passes -> Enum.map_join(passes, "; ", fn {w, ms} -> "#{w} " <> Enum.map_join(ms, " ", &seconds/1) end)
    end
  end

  defp durations(query) do
    names = Enum.map(@workers, &"Server.Jobs.#{&1}")

    from j in query,
      where: j.worker in ^names and j.state == "completed" and not is_nil(j.completed_at),
      select: {j.worker, fragment("(extract(epoch from ? - ?) * 1000)::bigint", j.completed_at, j.attempted_at)}
  end

  defp seconds(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp slowest(rows) do
    rows |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Enum.map(fn {w, ms} -> {w, Enum.max(ms)} end)
  end
end
