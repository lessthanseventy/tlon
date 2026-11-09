defmodule Server.Workline.Landing do
  @moduledoc """
  An approved workline's turn in the merge queue and what follows it: the landing itself and the
  train it rides, the requeue of a landing GitHub holds, and the reland of one it cannot merge.
  The rebase and gate are `Server.Workline.Merge`, the push and the PR `Server.Workline.Publish`.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Artifacts.Git
  alias Server.Workline.Review
  alias Server.Workline.Shared
  alias Server.Workline.Stage

  require Logger

  @discarded_cap 3

  @doc """
  Run `fun` as `thread_id`'s one landing: a second caller while it runs gets `{:error, :approving}`
  at once — a burst of approve clicks is one landing, not several racing over the same checkout.
  """
  def landing(thread_id, fun) do
    lock = {{:workline_landing, thread_id}, self()}

    if :global.set_lock(lock, [node()], 0) do
      try do
        fun.()
      after
        :global.del_lock(lock, [node()])
      end
    else
      {:error, :approving}
    end
  end

  @doc """
  Landings that went missing: open worklines at review, waiting on no one, whose approval still
  stands but with no landing queued or running (a `Server.Jobs.Land` Lifeline rescued past its
  attempts or Oban discarded). Each is queued again; returns those threads. One whose landing has
  been discarded #{@discarded_cap} times under its standing approval is left at review rather than crashing
  in a loop, and the sheriff is told once for that approval (a `dropped` post on the thread marks it); a
  fixed branch approved again starts over.
  """
  def requeue_stranded do
    stranded =
      Repo.all(from t in Thread, where: t.stage == "review" and t.state == "open" and is_nil(t.awaiting))

    for thread <- stranded,
        not Server.Office.Needs.landing?(thread),
        %{"by" => _, "sha" => _, "at" => _} = approval <- [Stage.approval(thread)],
        {:ok, queued} <- [requeue_or_drop(thread, approval)] do
      queued
    end
  end

  @doc """
  The merge queue's turn for `lead` with `others` queued behind it: a merge train. The cars (each
  still at review, unawaited, open and reviewed at its head) are stacked in order, each rebased on the
  one before, and the last, which holds them all, is gated ONCE (`Merge.stack/3`); a red gate is run
  again before it is believed, since one flake would otherwise stop every car. Green, they land in
  order: each is rebased onto the main the cars before it made and lands without a gate of its own
  only if that rebase gives the tree the train gated there (a main that moved some other way gives
  another: the lead then lands alone, gated alone, and a later car waits for its own turn). Red twice, or a car
  that won't stack: `lead` lands alone, gated alone, and every other car keeps its own turn, so the
  culprit is found and bounced by itself. Alone, it is `land_queued/2`. Opts as `land_queued/2`, and
  `on_cars: fn ids, split -> _ end`, told the thread ids taking the gate before it runs (the lead's
  alone when nothing rides) and again with `[lead]`, `true` when red twice splits the lead off.
  """
  def land_train(%Thread{} = lead, others, opts \\ []) do
    cars = Enum.filter([lead | others], &rideable?/1)
    on_cars = Keyword.get(opts, :on_cars, fn _, _ -> :ok end)

    if length(cars) < 2 or hd(cars).id != lead.id do
      on_cars.([lead.id], false)
      land_queued(lead, opts)
    else
      on_cars.(Enum.map(cars, & &1.id), false)
      train(cars, Keyword.put(opts, :on_cars, on_cars))
    end
  end

  @doc """
  The merge queue's turn for `thread` (`Server.Jobs.Land`): land `work/<slug>` rebased onto
  origin's main and gated there (`Server.Workline.Merge`). Green: merged, closed, published. A conflict or a red gate sends
  it back to build, its builder told why — the operator approved; the fix is the builder's. A thread
  no longer queued (re-parked, closed, moved on) is left alone. `opts[:merge]`/`opts[:gate]` swap the
  merger and the gate (tests). `{:ok, thread}` | `{:error, {:bounced, why}}`.
  """
  def land_queued(thread, opts \\ [])

  def land_queued(%Thread{stage: "review", awaiting: nil, state: "open"} = thread, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate(thread, &1, &2) end)
    repo = Git.root(thread)
    last? = Keyword.get(opts, :last, false)

    with :ok <- Review.reviewed_current(thread) do
      case merger.merge(repo, thread.slug, gate: gate) do
        {:ok, moved} ->
          landed(thread, Map.merge(moved, %{repo: repo, gated: moved.to}), Keyword.get(opts, :run, &Server.Cmd.run/3))

        {:error, {:interrupted, why}} when not last? ->
          {:error, {:interrupted, why}}

        {:error, {:interrupted, why}} ->
          Server.Sheriff.report(thread, "the merge queue was cut off three times: #{why}")
          Shared.bounce(thread, why, "the merge queue was cut off three times (#{why}); verify again, then approve")

        {:error, why} ->
          Server.Sheriff.report(thread, "the merge queue bounced it back to build: #{why}")

          Shared.bounce(
            thread,
            why,
            "the merge queue couldn't land it: #{why} Rebase work/#{thread.slug} onto origin/main, fix it test-first"
          )
      end
    end
  end

  def land_queued(%Thread{stage: "review", awaiting: nil, state: "closed"} = thread, _opts) do
    Shared.post_brief(
      thread,
      "⧗ its turn in the merge queue came, but the thread is closed — nothing landed. `tlon-cli reopen #{thread.id}` puts it back in the queue while its approval stands"
    )

    {:ok, thread}
  end

  def land_queued(thread, _opts), do: {:ok, thread}

  @doc """
  A landed workline whose PR GitHub can never merge (it conflicts with main, which moved under it
  after it landed): reopened and bounced to build, its builder told `why`, so it comes back through
  verify, review and the merge queue. `todo` replaces the default rebase instruction when it was
  something else that failed. Anything not `merged` is left as it is.
  """
  def reland(thread, why, todo \\ nil)

  def reland(%Thread{stage: "landed"} = thread, why, todo) do
    Server.Channel.reopen_if_closed(thread.id)
    Server.Tickets.undone_for(thread.id)

    Shared.bounce(
      Repo.get!(Thread, thread.id),
      why,
      todo ||
        "#{why}: main moved under it after it landed. Rebase work/#{thread.slug} onto origin/main, resolve it, test"
    )
  end

  def reland(thread, _why, _todo), do: {:ok, thread}

  @doc """
  GitHub merged a landed workline (`Server.Jobs.KeepUp` read its PR as `MERGED`; with no GitHub to
  publish to, its landing is the merge): recorded as its landing's `work_landed` (`landed_since/1`),
  its thread closed (its ticket done), and the issues its tickets own resolved naming `ref`, the PR.
  Only an open `merged` workline; anything else is left as it is.
  """
  def merged(%Thread{stage: "landed", state: "open"} = thread, ref) do
    record_landing(thread, "work_landed", %{"summary" => "merged: #{ref}", "evidence" => ref})
    {:ok, closed} = Server.Channel.close_thread(thread)
    Shared.post_brief(closed, "✓ merged: #{ref}")
    Server.Dossier.resolve_fixed(thread, ref)
    {:ok, closed}
  end

  def merged(thread, _ref), do: {:ok, thread}

  @doc """
  The landed worklines waiting on GitHub to merge their PR: open, `merged`, and the newest event of
  their landing about its PR, not its merge. `[%{thread, url, event}]`, `event` that newest one: a
  `check_failed` when GitHub won't merge it as it stands (`landing_blocked/2`).
  """
  def waiting_on_github do
    for t <- Repo.all(from t in Thread, where: t.state == "open" and t.stage == "landed"),
        waiting = pending_landing(t),
        do: waiting
  end

  @doc """
  GitHub won't merge a waiting landing as it stands (`why`): recorded on its landing, once until
  something moves it, which makes it a `pr_blocked` Need (`Server.Office.Needs`). `:ok`.
  """
  def landing_blocked(%Thread{} = thread, why) do
    with %{url: url, event: %{kind: kind}} when kind != "check_failed" <- pending_landing(thread),
         do: record_landing(thread, "check_failed", landing_check(url, 1, why))

    :ok
  end

  @doc """
  The operator's "rebase" for a landing GitHub isn't merging: back into the merge queue
  (`Server.Jobs.Land`, `reland_queued/2`), which lands it as it lands a fresh one. GitHub's own
  rebase is never asked for: its new head is one no gate ran on, so `tlon/check`, main's required
  check, never comes. `{:ok, thread}`, `{:error, :not_landing}` for a thread with no PR waiting on
  GitHub, or `{:error, why}` when it can't be queued.
  """
  def rebase_landing(thread) do
    with %{url: url} <- pending_landing(thread) || {:error, :not_landing},
         {:ok, _job} <- Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id, reland: true})) do
      record_landing(
        thread,
        "check_passed",
        landing_check(url, 0, "back in the merge queue to land again")
      )

      Shared.post_brief(
        thread,
        "⧗ back in the merge queue: #{url} lands once rebased onto main and green there, merged at the head it gated"
      )

      {:ok, thread}
    end
  end

  @doc """
  A waiting landing GitHub holds (`why`) for what a rebase and a gate fix (behind main, `tlon/check`
  missing on its head): back into the merge queue on its own (`reland_queued/2`, `auto`), no Need
  raised. Once per PR `head`: held again at a head it was already requeued at (or that a requeued
  landing armed auto-merge at, `merge_again/5`), or not queueable, it
  is blocked (`landing_blocked/2`), a `pr_blocked` Need. `:requeued` | `:ok` (blocked, not waiting,
  or already queued).
  """
  def requeue_blocked(%Thread{} = thread, why, head) do
    with %{url: url} <- pending_landing(thread),
         false <- Server.Office.Needs.landing?(thread) do
      if is_binary(head) and not requeued_at?(thread, head) and requeue(thread, url, why, head) == :ok,
        do: :requeued,
        else: landing_blocked(thread, why)
    else
      _ -> :ok
    end
  end

  @doc """
  The merge queue's turn for a landing put back in it (`rebase_landing/1`): `work/<slug>` rebased
  onto origin's main and gated there (`Server.Workline.Merge`), pushed, `tlon/check` posted on the sha
  it gated and its open PR merged at exactly that head (`Publish.merge_at/5`), as a fresh landing is.
  A rebase or gate that fails is refused as a fresh landing's is, back to build with why, its PR
  closed first (`reland/3`). Only an open `merged` workline still waiting on GitHub; anything else is
  left alone. `opts` as `land_queued/2`'s. `{:ok, thread}` | `{:error, {:bounced, why}}` |
  `{:error, {:interrupted, why}}` | `{:error, why}`.
  """
  def reland_queued(thread, opts \\ []) do
    case pending_landing(thread) do
      nil -> {:ok, thread}
      %{url: url} -> land_again(thread, url, opts)
    end
  end

  @doc """
  The operator's "close and reland": its PR closed and the workline back at build on its branch
  (`reland/3`), to come back through verify, review and the merge queue. `reland/3`'s result,
  `{:error, :not_landing}`, or `{:error, why}` when the PR won't close.
  """
  def reland_landing(thread, run \\ &Server.Cmd.run/3) do
    with %{url: url} <- pending_landing(thread) || {:error, :not_landing},
         why = "the operator closed its PR #{url} to reland it",
         :ok <- Server.Workline.Publish.close(Git.root(thread), url, "#{why}; the workline is back at build", run) do
      reland(thread, why, "#{why}. Rebase work/#{thread.slug} onto origin/main, test")
    end
  end

  @doc """
  The worklines GitHub merged (`merged/2`, their landing's `work_landed`) at or after `since`, newest
  first: `[%{id, thread_id, title, created_at}]`, `id` the event's.
  """
  def landed_since(%DateTime{} = since) do
    Repo.all(
      from e in Server.Event,
        join: t in Thread,
        on: t.id == e.thread_id,
        where: e.kind == "work_landed" and like(e.correlation, "workline:%:landing") and e.created_at >= ^since,
        order_by: [desc: e.id],
        select: %{id: e.id, thread_id: t.id, title: t.title, created_at: e.created_at}
    )
  end

  @doc """
  Publish a landed workline whose publish failed (`Server.Office.Needs`' `publish_failed`) again: the
  same push and PR its landing tried. `{:ok, pr_url}` | `{:auto_refused, pr_url, why}` | `:none` (no
  origin) | `{:error, why}` — a
  failure is recorded again; a workline whose last publish did not fail is refused.
  """
  def republish(thread, run \\ &Server.Cmd.run/3)

  def republish(%Thread{stage: "landed"} = thread, run) do
    if publish_failed?(thread),
      do: publish(thread, Git.root(thread), "⤴ republished", "work/#{thread.slug}", run),
      else: {:error, "#{thread.slug} has no failed publish to retry"}
  end

  def republish(%Thread{} = thread, _run), do: {:error, "##{thread.id} has not landed"}

  @doc """
  The operator opened a failed publish's PR by hand (`Server.Office.Needs`' `publish_failed`): `url`
  is recorded as its publish and its landing, so it waits on GitHub (`waiting_on_github/0`) and closes
  when GitHub merges it. `{:ok, thread}` | `{:error, why}` — a workline whose last publish did not fail
  is refused.
  """
  def published_by_hand(%Thread{stage: "landed", state: "open"} = thread, url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" -> {:error, "the PR's url, to wait on GitHub for"}
      not publish_failed?(thread) -> {:error, "#{thread.slug} has no failed publish to put away"}
      true -> by_hand(thread, url)
    end
  end

  def published_by_hand(%Thread{} = thread, _url), do: {:error, "##{thread.id} has no landing waiting on its PR"}

  @doc "The correlation a workline's publish is recorded under, as `check_passed` or `check_failed`."
  def publish_correlation(%Thread{slug: slug}), do: "workline:#{slug}:publish"

  @doc """
  Reopen a closed thread. A workline that was in the merge queue (at review, waiting on no one)
  goes back into it while its approval stands (`approval/1`); one whose branch moved since is left
  at review for its reviewer, saying so. `{:ok, thread}`.
  """
  def reopen(%Thread{} = thread) do
    Server.Channel.reopen_if_closed(thread.id)
    reopened = Repo.get!(Thread, thread.id)

    case reopened do
      %Thread{stage: "review", awaiting: nil} ->
        case Stage.approval(reopened) do
          %{"by" => by, "sha" => sha} ->
            Stage.queue(reopened, "reopened — #{by}'s approval at #{String.slice(sha, 0, 7)} still stands", by)

          nil ->
            Shared.post_brief(
              reopened,
              "reopened at review — no approval stands for work/#{reopened.slug} as it is now"
            )

            {:ok, reopened}
        end

      _ ->
        {:ok, reopened}
    end
  end

  @doc false
  def landing_check(url, exit, tail),
    do: %{"cmd" => "GitHub merge of #{url}", "exit" => exit, "url" => url, "tail" => tail}

  @doc false
  def record_landing(thread, kind, detail) do
    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: kind,
        correlation: "workline:#{thread.slug}:landing",
        detail: detail
      })
  end

  # landed: what changed rolls out and the branch goes to GitHub, where it is not merged yet — the
  # thread stays open until GitHub merges the PR (`merged/2`). With no GitHub, the landing is the merge.
  @doc false
  def finish(thread, %{repo: repo, from: from, to: to} = moved, run) do
    Server.Rollout.after_merge(%{repo: repo, from: from, to: to, thread_id: thread.id})
    publish(thread, repo, "⤵ landed as #{String.slice(to, 0, 7)}", String.slice(to, 0, 7), run, moved[:gated])
  rescue
    e ->
      why = "merged, but its close-out failed (not published to GitHub): #{Exception.message(e)}"
      require(Logger) && Logger.warning("workline #{thread.slug}: #{why}")
      unpublished(thread, "⚠ #{why}")
  end

  # `gated`: the sha the merge queue's gate passed on, posted as tlon/check; a republish has none
  @doc false
  def publish(thread, repo, landed, ref, run, gated \\ nil) do
    case Server.Workline.Publish.publish(repo, thread.slug, thread.title, run, gated: gated) do
      {:ok, url} = ok ->
        record_publish(thread, 0, url)
        record_landing(thread, "check_passed", landing_check(url, 0, "published"))

        Shared.post_brief(
          thread,
          "#{landed}; published as #{url} — the thread closes once GitHub reports it merged"
        )

        ok

      {:auto_refused, url, why} = refused ->
        record_publish(thread, 0, url)
        record_landing(thread, "check_failed", landing_check(url, 1, "merge refused: #{why}"))
        Shared.post_brief(thread, "#{landed}; published as #{url}, but GitHub refused to merge it: #{why}")
        refused

      :none ->
        record_publish(thread, 0, "no origin to publish to")
        Shared.post_brief(thread, landed)
        merged(thread, ref)
        :none

      {:error, why} = error ->
        unpublished(thread, "#{landed}, but not published to GitHub: #{why}")
        error
    end
  end

  # the failure is recorded for the operator's list (`Server.Office.Needs`' `publish_failed`), and the
  # sheriff is told too, so the work reaches main
  @doc false
  def unpublished(thread, why) do
    record_publish(thread, 1, why)
    Shared.post_brief(thread, why)
    Server.Sheriff.report(thread, "work/#{thread.slug} — #{why}")
  end

  @doc false
  def record_publish(thread, exit, tail) do
    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: thread.id,
        kind: if(exit == 0, do: "check_passed", else: "check_failed"),
        correlation: publish_correlation(thread),
        detail: %{"cmd" => "publish work/#{thread.slug}", "exit" => exit, "tail" => tail}
      })
  end

  @doc """
  The last `limit` worklines GitHub merged, newest first, in one query:
  `[%{subject, ref, landed_at}]` — the thread's title, the PR it merged as (`merged/2`'s `ref`) and when.
  """
  @spec recent_landings(pos_integer()) :: [%{subject: String.t(), ref: String.t() | nil, landed_at: DateTime.t()}]
  def recent_landings(limit) do
    from(e in Server.Event,
      join: t in Thread,
      on: t.id == e.thread_id,
      where: e.kind == "work_landed" and like(e.correlation, "workline:%:landing"),
      order_by: [desc: e.id],
      limit: ^limit,
      select: {t.title, e.detail, e.created_at}
    )
    |> Repo.all()
    |> Enum.map(fn {subject, detail, at} -> %{subject: subject, ref: (detail || %{})["evidence"], landed_at: at} end)
  end

  defp publish_failed?(thread) do
    Repo.one(
      from e in Server.Event,
        where:
          e.thread_id == ^thread.id and e.correlation == ^publish_correlation(thread) and
            e.kind in ["check_passed", "check_failed"],
        order_by: [desc: e.id],
        limit: 1,
        select: e.kind
    ) == "check_failed"
  end

  # the gate passed: flip it to merged unless it moved off review while the gate ran
  defp landed(thread, moved, run) do
    case Stage.flip(thread) do
      {:ok, flipped} ->
        finish(flipped, moved, run)
        Server.Jobs.enqueue(Server.Jobs.Retro.new(%{thread_id: flipped.id}))
        {:ok, flipped}

      {:error, {:moved, now}} ->
        Shared.post_brief(
          thread,
          "⚠ the merge queue's gate passed, but the workline moved to #{now} while it ran — nothing landed."
        )

        {:ok, Repo.get!(Thread, thread.id)}
    end
  end

  defp by_hand(thread, url) do
    record_publish(thread, 0, url)
    record_landing(thread, "check_passed", landing_check(url, 0, "opened by hand"))
    Shared.post_brief(thread, "its PR opened by hand: #{url} — the thread closes when GitHub merges it")
    {:ok, thread}
  end

  defp land_again(thread, url, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate(thread, &1, &2) end)
    run = Keyword.get(opts, :run, &Server.Cmd.run/3)
    auto? = opts[:auto] == true
    repo = Git.root(thread)

    case merger.merge(repo, thread.slug, gate: gate) do
      {:ok, %{to: sha}} ->
        merge_again(thread, url, repo, sha, run)

      {:error, {:interrupted, why}} = cut ->
        if opts[:last],
          do:
            record_landing(
              thread,
              "check_failed",
              landing_check(url, 1, "the merge queue's gate was cut off: #{why}")
            )

        cut

      {:error, why} when auto? ->
        record_landing(
          thread,
          "check_failed",
          landing_check(url, 1, "the merge queue couldn't land it again: #{why}")
        )

        Shared.post_brief(thread, "⚠ the merge queue couldn't land it again: #{why} — it waits on the operator")
        {:error, why}

      {:error, why} ->
        refuse_again(thread, url, repo, why, run)
    end
  end

  defp merge_again(thread, url, repo, sha, run) do
    branch = "work/#{thread.slug}"

    with :ok <- Server.Workline.Publish.replace_branch(repo, branch, run),
         Server.Workline.Publish.post_check(repo, sha, run),
         how when how in [:merged, :auto] <- Server.Workline.Publish.merge_at(repo, url, sha, branch, run) do
      said = if how == :merged, do: "merged", else: "auto-merge armed at that head"
      detail = landing_check(url, 0, "gated at #{String.slice(sha, 0, 7)}; #{said}")
      # GitHub merges an armed head itself: KeepUp requeueing it again would gate it for nothing
      detail = if how == :auto, do: Map.put(detail, "requeued_head", sha), else: detail
      record_landing(thread, "check_passed", detail)
      Shared.post_brief(thread, "⤵ landed again as #{String.slice(sha, 0, 7)}, gated on main; #{url}: #{said}")
      {:ok, thread}
    else
      {:error, why} ->
        record_landing(thread, "check_failed", landing_check(url, 1, "merge refused: #{why}"))
        Shared.post_brief(thread, "⚠ gated green at #{String.slice(sha, 0, 7)}, but GitHub refused it: #{why}")
        {:error, why}
    end
  end

  defp refuse_again(thread, url, repo, why, run) do
    Server.Sheriff.report(thread, "the merge queue couldn't land it again: #{why}")

    case Server.Workline.Publish.close(repo, url, "the merge queue couldn't land it again; back at build", run) do
      :ok ->
        reland(
          thread,
          why,
          "the merge queue couldn't land it again: #{why} Rebase work/#{thread.slug} onto origin/main, fix it test-first"
        )

      {:error, out} ->
        record_landing(
          thread,
          "check_failed",
          landing_check(url, 1, "#{why}; its PR wouldn't close: #{out}")
        )

        {:error, why}
    end
  end

  defp requeue(thread, url, why, head) do
    with {:ok, _job} <-
           Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id, reland: true, auto: true})) do
      detail =
        Map.put(landing_check(url, 0, "#{why}: back in the merge queue on its own"), "requeued_head", head)

      record_landing(thread, "check_passed", detail)
      Shared.post_brief(thread, "⧗ #{why} — back in the merge queue on its own: #{url} lands once rebased and gated")
      :ok
    end
  end

  defp requeued_at?(thread, head) do
    Repo.exists?(
      from e in Server.Event,
        where:
          e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:landing" and
            fragment("(?::jsonb ->> 'requeued_head') = ?", e.detail, ^head)
    )
  end

  defp rideable?(%Thread{stage: "review", awaiting: nil, state: "open"} = t), do: Review.reviewed_current(t) == :ok
  defp rideable?(_thread), do: false

  defp ride([{lead, _} = first | rest], repo, merger, opts) do
    run = Keyword.get(opts, :run, &Server.Cmd.run/3)

    case ride_on(first, repo, merger, run) do
      {:cont, :ok} ->
        Shared.post_brief(
          lead,
          "🚃 landed in a merge train with #{Enum.map_join(rest, ", ", fn {t, _} -> "##{t.id}" end)}: one gate for all of them"
        )

        _ = Enum.reduce_while(rest, :ok, fn car, :ok -> ride_on(car, repo, merger, run) end)
        {:ok, Repo.get!(Thread, lead.id)}

      {:halt, :ok} ->
        land_queued(lead, opts)
    end
  end

  defp ride_on({thread, car}, repo, merger, run) do
    certify = fn r, branch ->
      if merger.tree(r, branch) == car.tree, do: {:ok, :train}, else: {:error, :moved}
    end

    case merger.merge(repo, thread.slug, gate: certify) do
      {:ok, moved} ->
        landed(thread, Map.merge(moved, %{repo: repo, gated: moved.to}), run)
        {:cont, :ok}

      {:error, _} ->
        {:halt, :ok}
    end
  end

  defp train([lead | _] = cars, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    repo = Git.root(lead)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate_train(List.last(cars), &1, &2) end)
    slugs = Enum.map(cars, & &1.slug)
    stack = fn -> merger.stack(repo, slugs, gate: gate) end

    case with({:error, {:gate, _}} <- stack.(), do: stack.()) do
      {:ok, %{cars: stacked}} ->
        ride(Enum.zip(cars, stacked), repo, merger, opts)

      {:error, _} ->
        opts[:on_cars].([lead.id], true)
        land_queued(lead, opts)
    end
  end

  defp requeue_or_drop(thread, %{"by" => by, "sha" => sha, "at" => at} = approval) do
    if discarded_landings(thread, at) < @discarded_cap do
      Stage.queue(
        thread,
        "its landing was lost — #{by}'s approval at #{String.slice(sha, 0, 7)} still stands, queued again",
        by
      )
    else
      report_dropped(thread, approval)
      :dropped
    end
  end

  # Told once per approval: the post that says so carries the approval's id, so a later tick finds it
  # and stays quiet, while a fresh approval (a new id) is reported afresh.
  defp report_dropped(thread, %{"by" => by, "sha" => sha, "id" => id}) do
    told? =
      Repo.exists?(
        from m in Server.Message,
          where: m.thread_id == ^thread.id and fragment("?->>'dropped' = ?", m.payload, ^to_string(id))
      )

    if not told? do
      what =
        "its landing was dropped #{@discarded_cap} times and is no longer requeued: #{by}'s approval at " <>
          "#{String.slice(sha, 0, 7)} (#{sha}) stands, and the work waits at review"

      if Server.Sheriff.report(thread, what) == :ok do
        Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: what, payload: %{"dropped" => to_string(id)}})
      end
    end

    :ok
  end

  defp discarded_landings(%Thread{id: id}, since) do
    Repo.aggregate(
      from(j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Land" and j.state == "discarded" and j.inserted_at >= ^since and
            fragment("(? ->> 'thread_id')::int = ?", j.args, ^id)
      ),
      :count
    )
  end

  defp pending_landing(%Thread{stage: "landed", state: "open"} = thread) do
    case last_landing(thread) do
      %Server.Event{kind: kind, detail: %{"url" => url}} = e when kind != "work_landed" ->
        %{thread: thread, url: url, event: e}

      _ ->
        nil
    end
  end

  defp pending_landing(_thread), do: nil

  defp last_landing(thread) do
    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:landing",
        order_by: [desc: e.id],
        limit: 1
    )
  end
end
