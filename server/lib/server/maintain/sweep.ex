defmodule Server.Maintain.Sweep do
  @moduledoc """
  The Maintain back-edge (worklines slice 6): deterministic control-band sweeps with NO
  human in the invocation path — yet nothing it does is unsupervised, because every action
  is a nag message or a MACHINE-BORN flag that lands parked at the operator's gate.

  Bands (opts, defaults below):
    * a gate parked longer than `gate_stale_ms` → a reminder post (once per `renag_ms`)
    * a non-merged workline with no stage advance for `stalled_ms` → `Workline.flag/2`
      (once per slug; `maint-*` flags never flag themselves)

  Stateless: nag recency derives from the durable nag message, a flag from its slug row —
  so `Server.Jobs.Maintain` runs it on Oban's cron (one-brain piece E, slice 2) with nothing
  to carry between sweeps. A second node running it would race only on the slug UNIQUE index,
  where a lost race is a dropped changeset, not a duplicate.
  """

  import Ecto.Query

  alias Server.Channel
  alias Server.Event
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  @defaults [
    gate_stale_ms: to_timeout(day: 1),
    stalled_ms: to_timeout(day: 3),
    renag_ms: to_timeout(day: 1)
  ]

  @doc "Both sweeps, with the default bands unless `opts` names one."
  def run(opts \\ []) do
    opts = Keyword.merge(@defaults, opts)
    sweep_gates(opts)
    sweep_stalled(opts)
    :ok
  end

  defp sweep_gates(opts) do
    for thread <- parked_gates(),
        stale?(thread, opts[:gate_stale_ms]),
        not nagged_recently?(thread, opts[:renag_ms]) do
      post(thread, "⏸ workline #{thread.slug} still parked at #{thread.stage} — approve #{thread.id}")
    end

    :ok
  end

  defp nagged_recently?(thread, renag_ms) do
    last =
      Repo.one(
        from m in Server.Message,
          where: m.thread_id == ^thread.id and m.author == "tlon" and like(m.body, "% still parked at %"),
          order_by: [desc: m.id],
          limit: 1,
          select: m.created_at
      )

    last != nil and DateTime.diff(DateTime.utc_now(), last, :millisecond) < renag_ms
  end

  defp sweep_stalled(opts) do
    for thread <- stalled_candidates(),
        stale?(thread, opts[:stalled_ms]),
        not String.starts_with?(thread.slug, "maint-"),
        is_nil(Repo.get_by(Thread, slug: "maint-#{thread.slug}")) do
      case Workline.flag(
             %{title: "maintain: #{thread.slug} stalled at #{thread.stage}", slug: "maint-#{thread.slug}"},
             "breach: workline #{thread.slug} (##{thread.id}) has not advanced past #{thread.stage} " <>
               "within the control band — decide: push it, restaff it, or delete it."
           ) do
        {:ok, _flagged} -> :ok
        {:error, _changeset} -> :ok
      end
    end

    :ok
  end

  defp parked_gates do
    Repo.all(from t in Thread, where: t.state == "open" and not is_nil(t.awaiting))
  end

  defp stalled_candidates do
    Repo.all(
      from t in Thread,
        where: t.state == "open" and not is_nil(t.stage) and t.stage != "merged" and is_nil(t.awaiting)
    )
  end

  # Age from the LAST stage advance (or open) — the band is about progress, not existence.
  defp stale?(thread, band_ms) do
    last =
      Repo.one(
        from e in Event,
          where: e.thread_id == ^thread.id and e.kind == "stage_advanced",
          order_by: [desc: e.id],
          limit: 1,
          select: e.created_at
      ) || thread.created_at

    DateTime.diff(DateTime.utc_now(), last, :millisecond) >= band_ms
  end

  defp post(thread, body) do
    Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end
end
