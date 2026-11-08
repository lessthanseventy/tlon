defmodule Server.Jobs.Passes do
  @moduledoc """
  How long the per-tick passes (`Drain`, `Staff`, `Dispatch`, `KeepUp`) take, read off the rows Oban
  stamps on every run: the same span its `[:oban, :job, :stop]` telemetry reports, kept 7 days by the
  pruner, readable from `server:doctor` without a running node. `Staff` has concurrency 1 and a
  300 s unique period, so a pass that overruns its minute silently skips ticks: `slow/0` names the
  ones whose newest pass took over 30 s, and the box's Needs raise `health:job_slow` for them.

  `Maintain` is not here: it runs every half hour and takes 18-52 s by design.
  """
  import Ecto.Query

  alias Server.Repo

  @workers ~w(Drain Staff Dispatch KeepUp)
  @slow_ms 30_000
  @news_s 900

  @doc "Each pass worker's last `n` durations in ms, newest first: `[{\"Staff\", [41_000, 2_000]}]`; only workers that have run."
  def recent(n \\ 3) do
    rows = Repo.all(durations(from(j in Oban.Job, order_by: [desc: j.completed_at])))

    for short <- @workers,
        ms = Enum.take(for({worker, d} <- rows, worker == "Server.Jobs." <> short, do: d), n),
        ms != [],
        do: {short, ms}
  end

  @doc "The workers whose newest pass, finished in the last 15 minutes, took over 30 s: `[{\"Staff\", 41_000}]`."
  def slow do
    since = DateTime.add(DateTime.utc_now(), -@news_s)

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

    for {"Server.Jobs." <> short, ms} <- newest, ms > @slow_ms, do: {short, ms}
  end

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
end
