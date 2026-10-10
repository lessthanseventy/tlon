defmodule Server.Maintain.Sweep do
  @moduledoc """
  The Maintain back-edge (worklines slice 6): deterministic control-band sweeps with NO
  human in the invocation path — yet nothing it does is unsupervised, because every action
  is a nag message or a MACHINE-BORN flag that lands parked at the operator's gate.

  Bands (opts, defaults below):
    * a gate parked longer than `gate_stale_ms` → a reminder post (once per `renag_ms`)
    * a non-merged workline with no stage advance for `stalled_ms` → `Workline.flag/2`
      (once per slug; `maint-*` flags never flag themselves)
    * a workline quiet for `quiet_ms` (a lead whose window died is never idle) → a continuation,
      toward the budget that stops a stuck one on the operator

  And the board kept true, so its state can be trusted:

    * a ticket `doing` with no open thread tied to it → back to `backlog`, the reason in its body;
      a ticket tied as `promoted` to an open thread but not `doing` → `doing`
    * a worktree no thread is working in (`Server.Maintain.Strays`) → removed when it holds
      nothing, unless it is the lobby's, which the coworkers' home windows run in; one holding
      work stays, for the operator (the needs list's stranded work)
    * a fact or chat message still without an embedding (the embedder was down when it was
      written) → embedded now, a batch per sweep (`Server.Recall.embed_missing/1`)
    * a live fact that names code → probed against `origin/main` and given a `check_passed` or
      `check_failed` (`Server.Recall.Recheck`), the least recently checked first, a batch per sweep

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

  require Logger

  @defaults [
    gate_stale_ms: to_timeout(day: 1),
    stalled_ms: to_timeout(day: 3),
    renag_ms: to_timeout(day: 1),
    quiet_ms: to_timeout(hour: 1)
  ]

  @doc "Both sweeps, with the default bands unless `opts` names one."
  def run(opts \\ []) do
    quiet = to_timeout(minute: Server.OperatorConfig.setting("quiet_workline_minutes"))
    opts = @defaults |> Keyword.put(:quiet_ms, quiet) |> Keyword.merge(opts)
    sweep_gates(opts)
    sweep_stalled(opts)
    sweep_quiet(opts)
    sweep_tickets()
    sweep_worktrees()
    sweep_fact_rechecks()
    # embed-on-write is best-effort: what an embedder outage missed is caught up here
    _ = Server.Recall.embed_missing()
    :ok
  end

  # a lead whose window died never goes idle, so it never gets the continuation an idle schedules:
  # a workline quiet for the band is nudged here, toward the same budget, and so stops on the
  # operator if it is truly stuck
  defp sweep_quiet(opts) do
    since = DateTime.add(DateTime.utc_now(), -opts[:quiet_ms], :millisecond)

    for t <-
          Repo.all(
            from t in Thread,
              where: t.state == "open" and not is_nil(t.stage) and t.stage != "merged" and is_nil(t.awaiting)
          ),
        not Repo.exists?(from m in Server.Message, where: m.thread_id == ^t.id and m.created_at > ^since),
        do: Server.Workline.Continuation.run(t.id, quiet: true)

    :ok
  end

  defp sweep_tickets do
    open_tied = fn kinds ->
      Repo.all(
        from l in Server.TicketThread,
          join: t in Thread,
          on: t.id == l.thread_id,
          where: t.state == "open" and l.kind in ^kinds,
          select: l.ticket_id,
          distinct: true
      )
    end

    working = MapSet.new(open_tied.(~w(promoted relates)))
    started = open_tied.(~w(promoted))

    # a claimed ticket is worked by hand (`Server.Tickets.claim/2`): no thread works it
    for ticket <- Repo.all(from t in Server.Ticket, where: t.status == "doing"),
        not MapSet.member?(working, ticket.id),
        not Server.Tickets.claimed?(ticket) do
      note = "Back to the backlog #{Date.utc_today()}: no open thread was working on it."
      Server.Tickets.update(ticket, %{status: "backlog", body: String.trim("#{ticket.body}\n\n#{note}")})
    end

    for ticket <- Repo.all(from t in Server.Ticket, where: t.id in ^started and t.status in ~w(backlog todo)) do
      Server.Tickets.update(ticket, %{status: "doing"})
    end

    :ok
  end

  @recheck_batch 25

  defp sweep_fact_rechecks do
    last_check =
      from e in Event,
        where: e.kind in ["check_passed", "check_failed"] and like(e.detail, "%server recheck: %"),
        group_by: e.correlation,
        select: %{correlation: e.correlation, at: max(e.created_at)}

    # prose and ref-less facts record nothing, so the batch counts only facts that got a verdict
    from(f in Server.Fact,
      left_join: c in subquery(last_check),
      on: c.correlation == fragment("'fact:' || ?", f.id),
      where:
        is_nil(f.forgotten_at) and not is_nil(f.thread_id) and
          f.id not in subquery(from s in Server.Fact, where: not is_nil(s.supersedes), select: s.supersedes),
      order_by: [asc_nulls_first: c.at, asc: f.id]
    )
    |> Repo.all()
    |> Enum.reduce_while(@recheck_batch, fn fact, left ->
      left = if recheck(fact) == :skipped, do: left, else: left - 1
      if left == 0, do: {:halt, 0}, else: {:cont, left}
    end)
    |> then(fn _ -> :ok end)
  rescue
    e ->
      Logger.warning("fact recheck sweep failed: #{Exception.message(e)}")
      :ok
  end

  defp recheck(fact) do
    {:ok, verdict} = Server.Recall.Recheck.run(fact)
    verdict
  rescue
    e ->
      Logger.warning("recheck of fact #{fact.id} failed: #{Exception.message(e)}")
      :skipped
  end

  defp sweep_worktrees do
    reap_worktrees()
    :ok
  end

  @doc """
  The worktree sweep on its own, now (`tlon-cli reap`): every stray worktree removed unless it
  holds work, never the lobby's (every coworker's home window runs in it). Each as `{path, result}`,
  the result `Server.Worktree.remove/2`'s.
  """
  def reap_worktrees do
    for %{repo: repo, name: name, thread: thread} <- Server.Maintain.Strays.worktrees(),
        !(thread && Server.Channel.root_machine_thread?(thread)),
        do: {Server.Worktree.path(repo, name), Server.Worktree.remove(repo, name)}
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

  # worklines only: a plain thread waiting on a reply is not a parked gate
  defp parked_gates do
    Repo.all(from t in Thread, where: t.state == "open" and not is_nil(t.awaiting) and not is_nil(t.stage))
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
