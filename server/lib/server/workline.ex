defmodule Server.Workline do
  @moduledoc """
  The workline stage machine (worklines slice 1, design:
  `docs/plans/2026-08-27-ai-native-sdlc-workline-design.md`). A workline is a thread paired
  with a git folder `work/<slug>/`; its thread carries the stage:

      intent → spec → plan → build → verify → review → landed

  `advance/2` is the single mutation point and carries the invariant: NO advance without the
  stage's owed artifact (checked through the `Server.Workline.Artifacts` behaviour, recorded
  as a CHECK either way, correlation `workline:<slug>:artifact`). Gated transitions —
  spec→plan, review→merged, and a machine-born intent→spec — park in `awaiting: <operator>`
  instead of flipping; `approve/1` is the operator's completion verb, and its approval stands
  across commits that only touch `work/<slug>/` (an advance after one re-queues, never re-parks;
  `approval/1`). A reviewed change Andrew
  would see (`@user_visible` paths) also owes a QA pass before its gate (`qa_verdict/5`), when the
  bench seats a qa. Every completed flip
  records a `stage_advanced` event: the slice-6 ledger reads metrics out of rows that
  already exist.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Artifacts.Git
  alias Server.Workline.Brief
  alias Server.Workline.Grade
  alias Server.Workline.Scribe

  require Logger

  @stages ~w(intent spec plan build verify review landed)
  @owed %{
    "intent" => {:file, "intent.md"},
    "spec" => {:file, "spec.md"},
    "plan" => {:file, "plan.md"},
    "build" => :branch,
    "verify" => :checks,
    "review" => {:file, "review.md"}
  }
  # Who leads each stage, by bench archetype: the stage's kind of work picks its worker. intent and
  # merged keep whoever has the thread.
  @staff_by_stage %{
    "spec" => "planner",
    "plan" => "planner",
    "build" => "builder",
    "verify" => "builder",
    "review" => "reviewer"
  }
  # Stages whose EXIT waits on the operator; a machine-born intent gates its exit too.
  @gated ~w(spec review)
  # What Andrew sees: the office, and the operator API it reads (the office snapshot rides on it).
  @user_visible ~w(office/ server/lib/server/mcp/operator_api.ex server/lib/server/office)

  # The ring, the owed map, and the gate list drift independently unless something ties them:
  # every non-terminal stage MUST owe an artifact, every gated stage must be in the ring.
  for stage <- Enum.drop(@stages, -1) do
    Map.has_key?(@owed, stage) || raise "stage #{stage} has no owed artifact in @owed"
  end

  for stage <- @gated do
    stage in @stages || raise "gated stage #{stage} is not in @stages"
  end

  @doc "The stage ring, first to terminal."
  def stages, do: @stages

  # Any-stage entry (Slice 4D): a workline may open at any stage except the terminal one. Opening
  # LATER than intent sets the starting position — it does not retroactively owe the earlier stages'
  # artifacts; advances FROM there still owe theirs. `merged` is terminal, never an entry.
  @openable @stages -- ["landed"]

  @doc """
  Open a workline: a machine-scoped thread + the `work/<slug>/` name, at stage `:stage` (default
  "intent"; any-stage entry, Slice 4D). `{:ok, thread}`, `{:error, {:invalid_stage, s}}` for a
  terminal/unknown stage, or `{:error, changeset}` (a taken slug is a UNIQUE refusal).
  """
  def open(attrs) do
    stage = Map.get(attrs, :stage, "intent")

    if stage in @openable do
      attrs =
        attrs
        |> Map.put(:stage, stage)
        |> Map.put_new_lazy(:workspace_id, &Server.Bootstrap.default_workspace_id/0)

      with {:ok, thread} <-
             attrs |> Thread.workline_changeset() |> Repo.insert() |> Server.Bus.announce(:thread_opened) do
        # staffed first, so the brief — the wake from the entry stage — reaches its lead
        thread = restaff(thread)
        post_brief(thread, Brief.stage_message(thread))
        {:ok, thread}
      end
    else
      {:error, {:invalid_stage, stage}}
    end
  end

  @doc """
  Open a workline from a `title` (deriving the slug) at `stage` — the tertius `open`/`spike`/`build`
  verbs' server door (Slice 4D). `extra` carries workspace/project/parent. A slug collision gets a
  unique suffix. `{:ok, thread}` | `{:error, {:invalid_stage, s}}` | `{:error, changeset}`.
  """
  def open_titled(title, stage, extra \\ %{}) do
    open(Map.merge(%{title: title, slug: fresh_slug(title), stage: stage}, extra))
  end

  # A title → a fresh, unique work slug. Collisions (or an unslugifiable title) get a unique suffix.
  defp fresh_slug(title) do
    base = slugify_base(title)

    cond do
      base == "" -> "thread-#{System.unique_integer([:positive])}"
      slug_taken?(base) -> "#{base}-#{System.unique_integer([:positive])}"
      true -> base
    end
  end

  @doc """
  Promote a plain chat thread INTO the stage machine at `"build"` — the operator's verb
  (`tlon-cli track <id>`); nothing promotes on its own, so a plain thread stays a plain
  conversation. Slug derives from the title; a collision or unslugifiable title falls back to
  an id-suffixed name. Idempotent: an already-tracked thread is `{:ok, thread}` untouched. The
  ROOT machine thread is refused — the standing home is not a work item.
  """
  def promote(%Thread{stage: stage} = thread) when not is_nil(stage), do: {:ok, thread}

  def promote(%Thread{} = thread) do
    if Server.Channel.root_machine_thread?(thread) do
      {:error, :root_machine_thread}
    else
      with {:ok, tracked} <- do_promote(thread, promote_slug(thread)) do
        rename_worktree(thread, tracked)
        {:ok, tracked}
      end
    end
  end

  # The coworker has been committing on `work/t<id>` in `.worktrees/t<id>`; the slug is the
  # workline's name for both, so the checkout moves across. Best-effort: no repo, no worktree
  # yet, or a git refusal leaves the thread promoted and the checkout where it was.
  defp rename_worktree(%Thread{slug: nil} = before, %Thread{slug: slug}) when is_binary(slug) do
    case Server.repo_for_thread(before) do
      {:ok, repo} -> Server.Worktree.rename(repo, Server.Worktree.name_for(before), slug)
      {:error, _} -> :none
    end
  end

  defp rename_worktree(_before, _after), do: :none

  # Mirror flip/1: the stage landing and its ledger row commit together or not at all.
  # Re-reads INSIDE the transaction — two near-simultaneous callers on one thread must not
  # double-promote and skew the ledger with twin events. A changeset refusal (slug collision
  # under the fallback's own TOCTOU) rolls back to a tuple, never a raise — the caller surfaces it.
  defp do_promote(thread, slug) do
    result =
      Repo.transaction(fn ->
        fresh = Repo.get!(Thread, thread.id)
        if fresh.stage, do: {:already_tracked, fresh}, else: land_promotion(fresh, slug)
      end)

    case result do
      {:ok, {:already_tracked, fresh}} ->
        {:ok, fresh}

      {:ok, {:promoted, tracked}} ->
        Server.Bus.broadcast({:workline_advanced, tracked})
        tracked = unseat_manager(tracked)

        post_brief(tracked, Brief.stage_message(tracked))
        {:ok, tracked}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  # Runs inside do_promote's transaction: stage+slug landing and the ledger row are one write.
  defp land_promotion(fresh, slug) do
    fresh
    |> Thread.promote_changeset("build", slug)
    |> Repo.update()
    |> case do
      {:ok, tracked} ->
        {:ok, _event} =
          Dossier.record_event(%{
            thread_id: fresh.id,
            kind: "stage_advanced",
            correlation: "workline:#{slug}",
            detail: %{"from" => nil, "to" => "build", "promoted" => true}
          })

        {:promoted, tracked}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp promote_slug(%Thread{} = thread) do
    base = slugify_base(thread.title)

    cond do
      base == "" -> "thread-#{thread.id}"
      slug_taken?(base) -> "#{base}-#{thread.id}"
      true -> base
    end
  end

  defp slug_taken?(slug), do: Repo.get_by(Thread, slug: slug) != nil

  # A title → its bare slug candidate (closed charset, ≤40 chars). Shared by promote + open_titled.
  defp slugify_base(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, 40)
    |> String.trim("-")
  end

  @doc """
  Advance past the current stage. `{:ok, thread}` on a flip, `{:awaiting, thread}` when the
  transition gates on the operator, `{:error, {:artifact_missing, why}}` when the owed
  artifact isn't committed, `{:error, :awaiting_operator | :terminal | :not_a_workline}`
  otherwise; a hold off a gate (a worker's question, a stuck flag) does not block it.
  `opts[:artifacts]` swaps the checker (tests stub it; default is git).
  """
  def advance(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Git)

    with :ok <- still_open(thread),
         :ok <- advanceable(thread, checker),
         :ok <- verified_artifact(thread, checker),
         :ok <- qa_cleared(thread, opts) do
      if gated?(thread), do: park(thread, checker, opts), else: flip(thread)
    else
      {:error, {:artifact_missing, why}} when thread.stage == "verify" ->
        if Keyword.get(opts, :reverify, checker == Git),
          do: reverify(thread, why),
          else: {:error, {:artifact_missing, why}}

      {:error, {:artifact_missing, _}} = refused when thread.stage == "review" ->
        hand_to_qa(thread, opts) || refused

      other ->
        other
    end
  end

  # a reviewer that approved in review.md and advanced (rather than `submit_review`) still owes
  # QA: hand it to the qa seat as the verdict would, instead of refusing into a dead end
  defp hand_to_qa(thread, opts) do
    line = Keyword.get_lazy(opts, :review_line, fn -> Git.doc_line(thread, "review.md") end) || ""

    # review.md stays on the branch across rounds: with no verdict yet this round, an approval in it
    # is the last round's and owes nothing
    with true <- line =~ ~r/approve/i and not (line =~ ~r/request.?changes/i),
         false <- is_nil(since_review(thread, "workline:#{thread.slug}:review")) and reviewed_before?(thread),
         {seat, paths} <- qa_owed(thread, opts),
         false <- Server.Channel.thread_lead(thread.id) == seat.name do
      {:ok, to_qa(thread, seat, paths)}
    else
      _ -> nil
    end
  end

  # verify's evidence is the server's own run: a lead asking to advance past it (after fixing the
  # branch) is asking for a verify, which only the server can start — so it does
  defp reverify(thread, why) do
    case Server.Jobs.enqueue(Server.Jobs.Verify.new(%{thread_id: thread.id, slug: thread.slug})) do
      {:ok, _} -> {:error, {:artifact_missing, "#{why} — verify is queued; the server posts its result here"}}
      {:error, _} -> {:error, {:artifact_missing, why}}
    end
  end

  @doc """
  Complete a parked gate — the operator's verb (tlon-cli `approve`). RE-VERIFIES the owed
  artifact before flipping: a flag-parked intent (or an artifact that vanished since the
  park) cannot ride approval past the invariant. `{:ok, thread}`,
  `{:error, {:artifact_missing, why}}` (still parked), `{:error, :nothing_awaiting}`, or
  `{:error, :approving}` while another approval of it is landing.

  `skip_qa: reason` lands a review past an owed QA pass (parked or not): the skip is recorded as its
  QA verdict ("skipped by the operator: <reason>") and posted on the thread. Without it, or with a
  blank reason, an owed QA refuses as before.

  `as: handle` is the caller's seat (tlon-cli passes `TLON_AUTHOR`); nil is the operator. `as: "uqbar"`
  on a gate whose grade hit a limit (`limit_hit?/1`) is refused `{:error, :limit_hit}` before anything
  else, a `skip_qa` included. An approval is recorded `by` the caller, not the gate's holder.
  """
  def approve(thread, opts \\ [])

  def approve(%Thread{} = thread, opts) do
    reason = opts |> Keyword.get(:skip_qa) |> to_string() |> String.trim()

    cond do
      Keyword.get(opts, :as) == "uqbar" and limit_hit?(thread) ->
        {:error, :limit_hit}

      reason != "" and qa_owed(thread, opts) ->
        landing(thread.id, fn ->
          skip_qa(thread, reason)
          do_approve(thread, opts)
        end)

      thread.awaiting ->
        landing(thread.id, fn -> do_approve(thread, opts) end)

      true ->
        {:error, :nothing_awaiting}
    end
  end

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

  defp do_approve(thread, opts) do
    checker = Keyword.get(opts, :artifacts, Git)

    # A machine-born intent's approval IS its acceptance: server materializes intent.md from
    # the breach evidence so the chain stays intact and approve stays one verb. Only against
    # the REAL checker — a test stub must never make server commit into the live repo.
    if thread.stage == "intent" and thread.born == "machine" and checker == Git do
      Scribe.materialize_intent(thread)
    end

    with :ok <- verified_artifact(thread, checker),
         :ok <- reviewed_current(thread),
         :ok <- qa_cleared(thread, opts) do
      if queue?(thread, checker, opts),
        do: queue(thread, "approved", Keyword.get(opts, :as) || thread.awaiting || operator()),
        else: approve_now(thread, checker, opts)
    end
  end

  defp approve_now(thread, checker, opts) do
    with {:ok, landed} <- land(thread, checker, opts),
         {:ok, cleared} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         {:ok, flipped} <- flip(cleared) do
      if landed, do: finish(flipped, landed, Keyword.get(opts, :run, &System.cmd/3))
      {:ok, flipped}
    end
  end

  # The review gate's approval joins the merge queue (`Server.Jobs.Land`, one turn at a time, the
  # landings queued behind it riding as a merge train on one gate: `land_train/3`) — against the
  # real repo; a test's stub merger lands
  # inline, and `land: :queue | :now` says so outright.
  defp queue?(%Thread{stage: "review"}, checker, opts) do
    Keyword.get(opts, :land, if(checker == Git and not Keyword.has_key?(opts, :merge), do: :queue, else: :now)) ==
      :queue
  end

  defp queue?(_thread, _checker, _opts), do: false

  defp queue(thread, why, by) do
    with {:ok, queued} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         :ok <- if(match?(%{"by" => ^by}, approval(queued)), do: :ok, else: record_approval(queued, by)),
         {:ok, _job} <- Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id})) do
      post_brief(
        queued,
        "⧗ #{why} — in the merge queue: it lands once rebased onto main and green there, with any landings queued beside it on one gate"
      )

      {:ok, queued}
    else
      {:error, why} ->
        # back on whoever held the gate: from the row as written, or the change is a no-op on `thread`
        {:ok, _} =
          Thread
          |> Repo.get!(thread.id)
          |> Thread.workline_stage_changeset(%{awaiting: thread.awaiting})
          |> Repo.update()

        {:error, {:queue, why}}
    end
  end

  # what was approved is the branch at that commit: a later push needs approving again. Recorded
  # before its Land job, so the job's time is never before the approval's (second-truncated) one.
  # A db fault is returned, not raised: queue/3 has already cleared `awaiting` and puts it back.
  defp record_approval(thread, by) do
    with {:ok, _} <-
           Dossier.record_event(%{
             thread_id: thread.id,
             kind: "check_passed",
             correlation: "workline:#{thread.slug}:approval",
             detail: %{"cmd" => "approved by #{by}", "exit" => 0, "by" => by, "sha" => branch_head(thread)}
           }),
         do: :ok
  rescue
    e in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, Exception.message(e)}
  end

  @doc """
  The approval that still stands on a workline: the newest one recorded (`%{"by", "sha", "at", "id"}`,
  who approved it into the merge queue, the commit `work/<slug>` was at, when, and its event's id), while the
  branch's code is what it was then (its own docs, `work/<slug>/`, may have moved); nil once the
  code has changed, or when none was recorded. A requeue or reopen under it keeps it rather than
  recording another; the same code approved by someone else records theirs, the newest, so the
  landing names the latest approver.
  """
  def approval(%Thread{} = thread) do
    correlation = "workline:#{thread.slug}:approval"

    newest =
      Repo.one(
        from e in Server.Event,
          where: e.thread_id == ^thread.id and e.correlation == ^correlation,
          order_by: [desc: e.id],
          limit: 1,
          select: {e.id, e.detail, e.created_at}
      )

    with {id, %{"sha" => sha} = detail, at} when is_binary(sha) <- newest,
         head when is_binary(head) <- branch_head(thread),
         true <- same_code?(thread, sha, head),
         do: detail |> Map.take(["by", "sha"]) |> Map.merge(%{"at" => at, "id" => id}),
         else: (_ -> nil)
  end

  defp same_code?(thread, sha, head), do: compare_code(thread, sha, head) == :same

  @doc "The commit `work/<slug>` is at in the thread's repo, or nil without one."
  def branch_head(thread) do
    case System.cmd("git", ["-C", Git.root(thread), "rev-parse", "--verify", "--quiet", "work/#{thread.slug}^{commit}"],
           stderr_to_stdout: true
         ) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
  end

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
        case approval(reopened) do
          %{"by" => by, "sha" => sha} ->
            queue(reopened, "reopened — #{by}'s approval at #{String.slice(sha, 0, 7)} still stands", by)

          nil ->
            post_brief(reopened, "reopened at review — no approval stands for work/#{reopened.slug} as it is now")
            {:ok, reopened}
        end

      _ ->
        {:ok, reopened}
    end
  end

  @discarded_cap 3

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
        %{"by" => _, "sha" => _, "at" => _} = approval <- [approval(thread)],
        {:ok, queued} <- [requeue_or_drop(thread, approval)] do
      queued
    end
  end

  defp requeue_or_drop(thread, %{"by" => by, "sha" => sha, "at" => at} = approval) do
    if discarded_landings(thread, at) < @discarded_cap do
      queue(
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

    if !told? do
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

    with :ok <- reviewed_current(thread) do
      case merger.merge(repo, thread.slug, gate: gate) do
        {:ok, moved} ->
          landed(thread, Map.merge(moved, %{repo: repo, gated: moved.to}), Keyword.get(opts, :run, &System.cmd/3))

        {:error, {:interrupted, why}} when not last? ->
          {:error, {:interrupted, why}}

        {:error, {:interrupted, why}} ->
          Server.Sheriff.report(thread, "the merge queue's gate was cut off three times: #{why}")
          bounce(thread, why, "the merge queue's gate was cut off three times (#{why}); verify again, then approve")

        {:error, why} ->
          Server.Sheriff.report(thread, "the merge queue bounced it back to build: #{why}")

          bounce(
            thread,
            why,
            "the merge queue couldn't land it: #{why} Rebase work/#{thread.slug} onto origin/main, fix it test-first"
          )
      end
    end
  end

  def land_queued(%Thread{stage: "review", awaiting: nil, state: "closed"} = thread, _opts) do
    post_brief(
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

    bounce(
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
    post_brief(closed, "✓ merged: #{ref}")
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
      record_landing(thread, "check_passed", landing_check(url, 0, "back in the merge queue to land again"))

      post_brief(
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
  def reland_landing(thread, run \\ &System.cmd/3) do
    with %{url: url} <- pending_landing(thread) || {:error, :not_landing},
         why = "the operator closed its PR #{url} to reland it",
         :ok <- Server.Workline.Publish.close(Git.root(thread), url, "#{why}; the workline is back at build", run) do
      reland(thread, why, "#{why}. Rebase work/#{thread.slug} onto origin/main, test")
    end
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

  defp landing_check(url, exit, tail),
    do: %{"cmd" => "GitHub merge of #{url}", "exit" => exit, "url" => url, "tail" => tail}

  defp last_landing(thread) do
    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:landing",
        order_by: [desc: e.id],
        limit: 1
    )
  end

  defp record_landing(thread, kind, detail) do
    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: kind,
        correlation: "workline:#{thread.slug}:landing",
        detail: detail
      })
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
  What a workline's gate is decided on, in one line: at review, the reviewer's verdict line and the
  change's size, and what approving does; at another gate, the stage's doc that is ready.
  """
  def gate_summary(%Thread{stage: "review"} = thread) do
    verdict = Git.doc_line(thread, "review.md") || "no review.md yet"

    size =
      case Git.diffstat(thread) do
        {:ok, stat} -> stat
        {:error, why} -> why
      end

    risk = if grade = grade(thread), do: " · #{Grade.line(grade)}", else: ""
    "#{verdict} · #{size}#{risk} — approve to land it through the merge queue"
  end

  def gate_summary(%Thread{stage: stage, slug: slug}), do: "work/#{slug}/#{stage}.md is ready — approve to move on"

  @doc """
  The reviewer's verdict on its submitted review — `"approve"` or `"request_changes"` — recorded as
  evidence (`workline:<slug>:review`). Changes requested send it straight back to build, its builder
  told to read review.md: a review asking for changes never reaches the operator's gate. An approval
  is what a standing approval (`auto_land_risk` in the settings file) needs to land without them,
  and asks for the risk grade it is decided on (`Server.Jobs.Grade`); a change that owes QA is
  handed to the qa seat. An approval of a commit already approved this round is that same
  approval, `{:ok, thread}` and nothing recorded: a client retries a call whose connection
  dropped, and the verdict ends the reviewer's session under it (`Server.Staffing.end_review/1`: a
  review is a throwaway session, briefed fresh each round), so its `follow_ups:` (non-blocking
  findings) are posted once it has moved, for the lead it hands to (`follow_ups/4`). A verdict by the
  agent that built the branch is refused, `{:error, {:self_review, why}}` (`self_review/2`).
  `opts` as `advance/2`'s, and `paths:` the changed paths (tests).
  """
  def review_verdict(thread, verdict, author, opts \\ [])

  def review_verdict(%Thread{stage: "review"} = thread, verdict, author, opts)
      when verdict in ~w(approve request_changes) do
    sha = Keyword.get_lazy(opts, :branch_head, fn -> branch_head(thread) end)

    cond do
      why = self_review(thread, author) -> {:error, {:self_review, why}}
      verdict == "approve" and approved_at?(thread, sha) -> {:ok, thread}
      true -> record_verdict(thread, verdict, author, sha, opts)
    end
  end

  def review_verdict(%Thread{stage: "review"}, verdict, _author, _opts), do: {:error, {:bad_verdict, verdict}}

  def review_verdict(%Thread{stage: stage}, _verdict, _author, _opts), do: {:error, {:not_in_review, stage}}

  @doc """
  Why `author` may not review `thread`'s branch — it built it: the git author or `Tlon-Author:` of a
  commit on `work/<slug>` past main, its own review.md aside (`Server.BranchReview.builders/3`) — or
  nil when it may.
  """
  def self_review(%Thread{slug: slug} = thread, author) do
    root = Git.root(thread)

    builders =
      Server.BranchReview.builders(root, "#{main_ref(root) || "main"}..work/#{slug}", ["work/#{slug}/review.md"])

    if Server.BranchReview.built?(author, builders),
      do: "#{author} authored a commit on work/#{slug}: its review is someone else's, never the builder's"
  end

  @doc """
  The qa seat's verdict on a reviewed change it drove (`submit_qa`): `"pass"` or `"fail"`, its report
  (what it pressed and the screen text it saw) recorded as evidence (`workline:<slug>:qa`). A fail
  sends it back to build with the finding, as a review requesting changes does; a pass advances it
  to the merge gate. Its `follow_ups:` are posted once it has moved, for the lead it hands to
  (`follow_ups/4`). `opts` as `advance/2`'s, plus `session_id:`, the QA seat's connection, stamped
  on the `qa by` check (#679); the `cmd` string itself is what `Diary.verdict/1` parses, unchanged.
  """
  def qa_verdict(thread, verdict, author, report, opts \\ [])

  def qa_verdict(%Thread{stage: "review"} = thread, verdict, author, report, opts) when verdict in ~w(pass fail) do
    {:ok, _} =
      Dossier.record_check(
        %{
          thread_id: thread.id,
          cmd: "qa by #{author}",
          exit: if(verdict == "pass", do: 0, else: 1),
          tail: report,
          correlation: "workline:#{thread.slug}:qa"
        },
        session_id: opts[:session_id]
      )

    by = Server.Authorship.label(author, opts[:session_id])

    outcome =
      if verdict == "fail" do
        bounce(
          thread,
          "QA found a problem",
          "QA (#{by}) drove it and found:\n\n#{report}\n\nFix it test-first",
          author
        )
      else
        post_brief(thread, "✓ QA passed (#{by}):\n\n#{report}")
        advance(Repo.get!(Thread, thread.id), opts)
      end

    {:ok, _} = follow_ups(thread, author, Keyword.get(opts, :follow_ups, []), :qa)
    outcome
  end

  def qa_verdict(%Thread{stage: "review"}, verdict, _author, _report, _opts), do: {:error, {:bad_verdict, verdict}}
  def qa_verdict(%Thread{stage: stage}, _verdict, _author, _report, _opts), do: {:error, {:not_in_review, stage}}

  @doc """
  A risk grade just recorded for `thread` (`Server.Jobs.Grade`): a gate parked on the operator
  that the grade now lets land under the standing approval joins the merge queue; anything else
  is left as it is. `{:ok, thread}`. `opts` as `advance/2`'s.
  """
  def graded(%Thread{} = thread, opts \\ []) do
    thread = Repo.get!(Thread, thread.id)
    checker = Keyword.get(opts, :artifacts, Git)

    if thread.stage == "review" and thread.awaiting == operator() and auto_land?(thread, checker, opts),
      do: queue(thread, auto_land_note(thread, opts), "auto_land_risk"),
      else: {:ok, thread}
  end

  # A standing approval: the operator's `auto_land_risk` — a reviewed-and-approved workline whose
  # risk grade has no axis over it (and no limit hit, no decision left open) lands without them,
  # through the same gated queue. Off unless set; a test hands the threshold outright.
  # A builder with a good enough record has earned a step more of it (`Server.Trust`).
  defp auto_land?(thread, checker, opts) do
    max = Keyword.get_lazy(opts, :auto_land_risk, fn -> if checker == Git, do: auto_land_risk() end)

    is_integer(max) and review_approved?(thread) and
      Grade.allows?(grade(thread), elem(Server.Trust.allowance(thread, max), 0)) and
      qa_cleared(thread, opts) == :ok
  end

  defp auto_land_note(thread, opts) do
    {max, earned} = Server.Trust.allowance(thread, Keyword.get_lazy(opts, :auto_land_risk, &auto_land_risk/0))

    by =
      if earned,
        do:
          ": one over your setting, earned by #{earned.name}, who landed #{earned.first_time} of their last #{earned.led} builds first time",
        else: ""

    "auto-approved by your standing approval (reviewed; #{Grade.line(grade(thread))}, none over #{max}#{by})"
  end

  defp auto_land_risk, do: Server.OperatorConfig.setting("auto_land_risk")

  @doc """
  The limits the newest risk grade since the workline entered review hit (`Grade.limits/1`): `[]`
  when none, ungraded, or the grader failed.
  """
  def grade_limits(%Thread{} = thread) do
    case grade(thread) do
      %{"limits" => [_ | _] = limits} -> limits
      _ -> []
    end
  end

  @doc """
  Whether the newest risk grade hit a limit: such a gate is the operator's alone. An ungraded
  workline, or a failed grade, is not limit-hit.
  """
  def limit_hit?(%Thread{} = thread), do: grade_limits(thread) != []

  # the newest grade since the workline last entered review: nil if none, or the grader failed
  defp grade(thread) do
    case since_review(thread, "workline:#{thread.slug}:grade") do
      %{kind: "check_passed", detail: grade} -> grade
      _ -> nil
    end
  end

  defp review_approved?(thread),
    do: match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:review"))

  # the newest event of `correlation` since the workline last entered review
  defp since_review(thread, correlation) do
    entered =
      Repo.one(
        from e in Server.Event,
          where:
            e.thread_id == ^thread.id and e.kind == "stage_advanced" and
              fragment("(?::jsonb ->> 'to') = 'review'", e.detail),
          select: max(e.id)
      ) || 0

    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.correlation == ^correlation and e.id > ^entered,
        order_by: [desc: e.id],
        limit: 1
    )
  end

  defp bounce(thread, why, headline, by \\ nil) do
    {:ok, _} =
      move_back(
        thread,
        "build",
        why,
        "↩ back to build — #{headline}, then advance_stage; it comes back through verify and review.",
        fn _ -> :ok end,
        by
      )

    {:error, {:bounced, why}}
  end

  @doc """
  A red verify goes back to build on the same branch, its builder told what broke: the build is
  kept and fixed with its original context, never redone. Only from verify — a workline already
  moved on is left where it is. `{:ok, thread}` | `{:error, {:not_at, stage}}`.
  """
  def red_verify(%Thread{} = thread, finding) do
    move_back(
      thread,
      "build",
      "verify is red",
      "↩ back to build — verify is red: #{finding}\n\nFix it test-first on the same branch, then advance_stage; it comes back through verify and review.",
      fn
        %Thread{stage: "verify"} -> :ok
        %Thread{stage: stage} -> {:error, {:not_at, stage}}
      end,
      nil
    )
  end

  @doc """
  Staff `thread`'s current stage again from the bench as it is now — after a shift change, so a
  workline led by someone gone off shift is picked up by the crew on, the way any stage is staffed.
  `{:ok, thread}`.
  """
  def restaff_now(%Thread{} = thread), do: {:ok, restaff(thread)}

  @doc """
  Send `thread` back to an earlier working stage (`spec`, `plan` or `build`) on the same thread and
  branch: what was built and reviewed stays, and the stage's lead is told to improve it, not redo
  it. Back to build is the call of the workline's lead (its reviewer, QA or builder); back to plan or
  spec reshapes the build, a coherence call, so it is the tech lead's (`Server.Coworker.lead/1`) or
  the operator's. An open workline only, and not while its verify or landing is queued or running:
  either would move it on from under the send-back. `{:ok, thread}` | `{:error, {:not_movable,
  stage}}` | `{:error, {:in_flight, why}}` | `{:error, {:not_behind, stage}}` | `{:error, {:not_yours, why}}`.
  """
  def send_back(%Thread{} = thread, to, why, by) do
    allowed = fn locked ->
      with :ok <- movable(locked),
           :ok <- not_in_flight(locked),
           :ok <- behind(locked, to),
           do: may_send_back(locked, to, by)
    end

    move_back(thread, to, "sent back by #{by}: #{why}", send_back_brief(to, why, by), allowed, by)
  end

  @doc """
  A reviewer's or QA's non-blocking findings, posted on the workline for the lead its verdict hands
  to, so they are posted after the verdict moves it (`review_verdict/4`, `qa_verdict/5`): the builder
  on a bounce, the qa seat when QA is owed, and the operator when the thread is handed to their gate
  and its lead is still the author, whose session the verdict ended. One message, each text numbered
  (its first line the title, the rest the detail), blanks and repeated titles dropped
  (`follow_up_items/1`). None becomes a ticket here: the lead fixes what sits in the change's own
  lines before it lands, drops the rest, or defers one with `file_ticket`, which matches it against
  open tickets. Filing every finding grew the backlog faster than the office closed it. `{:ok,
  items}`, the items posted.
  """
  def follow_ups(%Thread{} = thread, author, items, door \\ :review) do
    items = follow_up_items(items)

    if items != [] do
      lead = Server.Channel.thread_lead(thread.id)
      to = if lead && lead != author, do: "@#{lead} ", else: "@#{operator()} "
      list = items |> Enum.with_index(1) |> Enum.map_join("\n", fn {text, i} -> "#{i}. #{text}" end)

      post_brief(
        thread,
        "#{to}follow-ups from #{author}'s #{door}:\n#{list}\n\n" <>
          "Fix any that sits in lines this change already touches before it lands. Drop the rest, or " <>
          "defer one someone would act on within a week with file_ticket (it is checked against open tickets)."
      )
    end

    {:ok, items}
  end

  @doc "The follow-ups `follow_ups/4` would post from `items`: trimmed, blanks and repeated titles dropped."
  def follow_up_items(items),
    do: items |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq_by(&follow_up_title/1)

  @doc """
  Lift the hold on a closing workline's follow-ups so intake routes them. One that closed without
  merging says so in each ticket's body, for the manager to check it still applies.
  """
  def release_follow_ups(%Thread{} = thread) do
    held = thread.id |> tied_follow_ups() |> Enum.filter(&("held" in &1.labels))

    note =
      if thread.stage == "landed",
        do: "",
        else: "\n\nIts workline (##{thread.id}) closed without merging: check this still applies."

    for t <- held,
        do: {:ok, _} = Server.Tickets.update(t, %{labels: t.labels -- ["held"], body: (t.body || "") <> note})

    if held != [],
      do: post_brief(thread, "↗ follow-ups to intake: " <> Enum.map_join(held, ", ", &"##{&1.id} #{&1.title}"))

    :ok
  end

  @doc """
  The Maintain back-edge's verb: open a MACHINE-BORN workline already parked at the intent
  gate, breach evidence as the opening message. Nothing advances until the operator
  approves — the monitor acts with no human in the invocation path, yet never unsupervised.
  """
  def flag(attrs, evidence) do
    with {:ok, thread} <- open(Map.put(attrs, :born, "machine")) do
      post_brief(thread, evidence)
      {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: operator()}) |> Repo.update()
      Server.Bus.broadcast({:workline_gated, parked})
      post_brief(parked, Brief.gate_message(parked))
      {:ok, parked}
    end
  end

  defp advanceable(%Thread{stage: nil}, _checker), do: {:error, :not_a_workline}
  defp advanceable(%Thread{stage: "landed"}, _checker), do: {:error, :terminal}

  # Only a gate's hold waits for approve. Off a gate the hold is a question or a stuck flag about the
  # missing artifact, which the artifact answers — or a green verify would sit behind it.
  defp advanceable(%Thread{awaiting: awaiting} = thread, checker) when not is_nil(awaiting) do
    if at_gate?(thread, artifacts: checker),
      do: {:error, :awaiting_operator},
      else: advanceable(%{thread | awaiting: nil}, checker)
  end

  defp advanceable(%Thread{stage: stage}, _checker) when stage in @stages, do: :ok
  # A stage outside the ring (hand-edited row, drifted data) is a typed refusal, not a crash.
  defp advanceable(%Thread{stage: stage}, _checker), do: {:error, {:invalid_stage, stage}}

  # The owed-artifact check, recorded as a CHECK either way — the audit half of the invariant.
  defp verified_artifact(thread, checker) do
    requirement = Map.fetch!(@owed, thread.stage)

    case owed_artifact(thread, checker) do
      {:ok, evidence} ->
        record_artifact_check(thread, requirement, 0, evidence)
        :ok

      {:error, why} ->
        record_artifact_check(thread, requirement, 1, why)
        {:error, {:artifact_missing, why}}
    end
  end

  defp record_artifact_check(thread, requirement, exit_code, tail) do
    Dossier.record_check(%{
      thread_id: thread.id,
      cmd: "workline artifact #{describe(requirement)}",
      exit: exit_code,
      tail: tail,
      # Stage-suffixed so the ledger can filter per-stage history on the indexed column.
      correlation: "workline:#{thread.slug}:artifact:#{thread.stage}"
    })
  end

  defp describe({:file, name}), do: name
  defp describe(other), do: to_string(other)

  @doc """
  Whether a workline stands at its gate — a gated stage whose owed artifact is there (and at review,
  no QA owed), which is when `advance` parks it — so an `awaiting` on it is that gate, which only an
  approval clears. Anywhere else (an ungated stage, a gated one whose artifact isn't written yet, or
  a review still owing QA) it is a worker's question, which a reply clears. A machine-born intent parks before its artifact by design: always a gate.
  `opts[:artifacts]` swaps the checker (tests).
  """
  def at_gate?(thread, opts \\ [])
  def at_gate?(%Thread{stage: "intent", born: "machine"}, _opts), do: true

  def at_gate?(%Thread{stage: stage} = thread, opts) do
    stage in @gated and match?({:ok, _}, Keyword.get(opts, :artifacts, Git).check(thread, Map.fetch!(@owed, stage))) and
      qa_cleared(thread, opts) == :ok
  rescue
    # an artifact that can't even be checked (no slug, no repo): the cautious reading, a gate
    _ -> true
  end

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

  # An approval stands across commits that only touched work/<slug>/ (`approval/1`): a reviewer
  # re-committing review.md and advancing again re-queues the code, it does not ask for it twice.
  defp park(%Thread{stage: "review"} = thread, checker, opts) do
    case approval(thread) do
      %{"by" => by, "sha" => sha} ->
        queue(thread, "#{by}'s approval at #{String.slice(sha, 0, 7)} still stands", by)

      nil ->
        if auto_land?(thread, checker, opts),
          do: queue(thread, auto_land_note(thread, opts), "auto_land_risk"),
          else: park_on_operator(thread, checker)
    end
  end

  defp park(thread, checker, _opts), do: park_on_operator(thread, checker)

  defp park_on_operator(thread, checker) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: operator()}) |> Repo.update()
    Server.Bus.broadcast({:workline_gated, parked})
    proof = if parked.stage == "review", do: proof(parked, artifacts: checker)
    post_brief(parked, Brief.gate_message(parked, proof))
    {:awaiting, parked}
  end

  @doc """
  The proof a workline carries into its merge gate, read now from git and the event log: each
  stage's owed artifact from the one it was opened at up to the current one, in the checker's
  words (verify's is `checks`; a workline opened at build never owed an intent, spec or plan), the
  newest verify check per command with its measured exit (five, newest first), and the branch's
  diff against HEAD. `%{artifacts: [{stage, {:ok | :error, why}}], checks: [%{cmd, exit}], diff:
  {:ok | :error, text}}`. `opts[:artifacts]` swaps the checker.
  """
  def proof(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Git)

    upto =
      @stages
      |> Enum.take(Enum.find_index(@stages, &(&1 == thread.stage)) + 1)
      |> Enum.drop(Enum.find_index(@stages, &(&1 == entry_stage(thread))) || 0)

    %{
      artifacts:
        for(stage <- upto, req = @owed[stage], req not in [nil, :checks], do: {stage, checker.check(thread, req)}),
      checks: verify_checks(thread),
      diff: Git.diffstat(thread)
    }
  end

  defp verify_checks(thread) do
    correlation = "workline:#{thread.slug}:verify"

    from(e in Server.Event,
      where: e.thread_id == ^thread.id and e.correlation == ^correlation and e.kind in ["check_passed", "check_failed"],
      order_by: [desc: e.id]
    )
    |> Repo.all()
    |> Enum.uniq_by(& &1.detail["cmd"])
    |> Enum.take(5)
    |> Enum.map(&%{cmd: &1.detail["cmd"], exit: &1.detail["exit"]})
  end

  # One transaction: the stage flip and its ledger row commit together or not at all, on the row
  # locked FOR UPDATE and only from the stage `thread` was read at, open: a landing or an advance
  # working from a stale read (a bounce, a second advance, a close since) flips nothing,
  # `{:error, {:moved, stage}}`.
  defp flip(thread) do
    to = next(thread.stage)

    fn ->
      locked = Repo.one!(from t in Thread, where: t.id == ^thread.id, lock: "FOR UPDATE")

      if locked.stage != thread.stage or locked.state != "open",
        do: Repo.rollback({:moved, if(locked.state == "open", do: locked.stage, else: "closed")})

      {:ok, flipped} = locked |> Thread.workline_stage_changeset(%{stage: to, awaiting: nil}) |> Repo.update()

      {:ok, _event} =
        Dossier.record_event(%{
          thread_id: thread.id,
          kind: "stage_advanced",
          correlation: "workline:#{thread.slug}",
          detail: %{"from" => thread.stage, "to" => to}
        })

      flipped
    end
    |> Repo.transaction()
    |> case do
      {:ok, flipped} -> flipped_after(flipped)
      {:error, moved} -> {:error, moved}
    end
  end

  # The brief IS the wake: a server-authored message rides the lead-wake path (slice 2).
  # Best-effort — a post failure never blocks the (already durable) transition.
  defp post_brief(thread, body) do
    Server.Channel.post(%{thread_id: thread.id, author: "tlon", body: body})
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp next(stage), do: Enum.at(@stages, Enum.find_index(@stages, &(&1 == stage)) + 1)

  @doc """
  Is the current stage's owed artifact there? The turn-end continuation
  (`Server.Workline.Continuation`) and the `/api/threads/:id` brief ask this without advancing. `:none` for a plain thread or a
  merged workline, `{:ok, why}` when committed, `{:error, why}` when missing — `why` in the
  checker's words (`Server.Workline.Artifacts`).
  """
  def owed_status(thread, opts \\ [])
  def owed_status(%Thread{stage: nil}, _opts), do: :none
  def owed_status(%Thread{stage: "landed"}, _opts), do: :none

  def owed_status(%Thread{} = thread, opts) do
    checker = Keyword.get(opts, :artifacts, Git)

    # A question, not a move: only advance and approve record the artifact check, or every brief
    # and turn-end nudge writes one (two at the same instant when both ask).
    with {:ok, _} <- owed_artifact(thread, checker),
         :ok <- qa_cleared(thread, opts) do
      {:ok, "#{thread.stage} artifact committed"}
    else
      {:error, {:artifact_missing, why}} -> {:error, why}
      {:error, why} when is_binary(why) -> {:error, why}
    end
  end

  @doc "The bench archetype that leads a workline at `stage` (planner, builder, reviewer), or nil."
  def staff_kind(stage), do: @staff_by_stage[stage]

  @doc "Whether `thread` owes a QA pass at review and its qa seat is the one leading it. `opts` as `advance/2`'s."
  def qa_leads?(thread, opts \\ []) do
    case qa_owed(thread, opts) do
      {seat, _paths} -> Server.Channel.thread_lead(thread.id) == seat.name
      nil -> false
    end
  end

  # Each stage is led by its kind of worker from the workspace's bench, so a workline hands itself
  # on as it moves; intent by the bench's lead (its first builder), who takes the ask in. Best-effort (the
  # stage already flipped; a restaff fault must not fail the advance). A workspace without that kind
  # keeps the current lead — quietly, except at review: a builder holding its own review is posted.
  defp restaff(%Thread{stage: "intent", workspace_id: ws} = thread) when not is_nil(ws) do
    ws
    |> Server.Workspaces.bench()
    |> Server.Coworker.lead()
    |> case do
      %Server.Coworker{name: name} -> hand_to(thread, "lead", name)
      nil -> thread
    end
  rescue
    _ -> thread
  end

  defp restaff(%Thread{stage: stage} = thread) do
    case @staff_by_stage[stage] do
      nil -> thread
      kind -> restaff(thread, kind)
    end
  end

  defp restaff(%Thread{workspace_id: nil} = thread, kind), do: restaff_miss(thread, kind, "no workspace bound")

  # One coworker, one workline: a lead already of this kind keeps it (spec→plan, build→verify);
  # else the best of the kind not leading another live workline by grade × specialty (Roster.pick;
  # one only waiting on the operator does not count — its session waits in its own window); else,
  # the kind being on the bench but all busy, one more is hired. A kind the bench lacks is never invented.
  defp restaff(thread, kind) do
    bench = Server.Workspaces.bench(thread.workspace_id)
    of_kind = Enum.filter(bench, &(&1.archetype == kind))
    current = Server.Channel.thread_lead(thread.id)
    free = Enum.reject(of_kind, &leading_another?(&1, thread))

    cond do
      of_kind == [] ->
        restaff_miss(thread, kind, "no #{kind} on the workspace's bench")

      Enum.any?(of_kind, &(&1.name == current)) ->
        thread

      free != [] ->
        # the lead going off: off shift after a shift change, so looked up on the whole bench
        builder = thread.workspace_id |> Server.Workspaces.bench_all() |> Enum.find(&(&1.name == current))
        candidates = Enum.map(free, &%{coworker: &1, model: seat_model(thread.workspace_id, &1)})
        {pick, short} = Server.Roster.pick(candidates, wanted(thread, kind, builder))
        hand_to(thread, kind, pick.name, shortfall(short, builder, thread.workspace_id))

      true ->
        hire_for(thread, kind, of_kind)
    end
  rescue
    e -> restaff_miss(thread, kind, Exception.message(e))
  end

  @doc """
  Hand a junior's workline up a grade (roster design §3): to the free senior (else greybeard) of
  its kind nearest its specialty, saying why on the thread. `{:escalated, name}`, or `:none` when
  the lead is no junior or nobody above it is free — the caller's usual path (the sheriff) then holds.
  """
  def escalate(%Thread{workspace_id: ws} = thread, why) when not is_nil(ws) do
    bench = Server.Workspaces.bench(ws)
    current = Server.Channel.thread_lead(thread.id)

    with %Server.Coworker{grade: "junior", archetype: kind} = junior <-
           ws |> Server.Workspaces.bench_all() |> Enum.find(&(&1.name == current)),
         [_ | _] = above <-
           Enum.filter(
             bench,
             &(&1.archetype == kind and &1.grade in ["senior", "greybeard"] and not leading_another?(&1, thread))
           ),
         {%Server.Coworker{name: name}, _} <-
           Server.Roster.pick(Enum.map(above, &%{coworker: &1, model: nil}), %{
             grade: "senior",
             specialty: junior.specialty
           }),
         {:ok, _} <- Server.Channel.assign_lead(thread.id, name) do
      close_leaf(thread)

      {:ok, _} =
        Server.Channel.post(%{
          thread_id: thread.id,
          author: "tlon",
          body: "↑ #{name} takes this from #{current}: #{why}. Pick it up from the brief.",
          payload: %{"escalated_from" => current}
        })

      {:escalated, name}
    else
      _ -> :none
    end
  end

  def escalate(_thread, _why), do: :none

  @doc """
  The server's pick of a `kind` on `workspace_id`'s bench for an ask (`text`), when a manager
  names no lead (`staff_child`): free seats first (leading no other live workline), by the grade
  the manager gave (else `Server.Roster.wanted_grade/2`'s) and the area the ask names. nil for a
  bench with none of the kind.
  """
  def suggest_lead(workspace_id, kind, text, grade \\ nil) do
    of_kind = workspace_id |> Server.Workspaces.bench() |> Enum.filter(&(&1.archetype == kind))
    free = Enum.reject(of_kind, &leading_another?(&1, %Thread{id: 0}))
    want = %{grade: Server.Roster.wanted_grade(text, grade), specialty: Server.Roster.specialty_of(text)}

    case Server.Roster.pick(Enum.map(if(free == [], do: of_kind, else: free), &%{coworker: &1, model: nil}), want) do
      {%Server.Coworker{name: name}, _} -> name
      nil -> nil
    end
  end

  @doc """
  Who leads `thread` when a manager asks for `wanted` (`staff_child`): them, when they are of the
  stage's kind (intent takes anyone on the bench) and lead no other live workline — else whoever
  staffing put there when the workline opened, and why. A pick from off the bench (a registered
  agent the bench does not seat), or a workline staffing left without a lead, takes the pick as
  asked. A pick off shift counts as on the bench: a manager may ask for someone off shift by name,
  and the kind and busy checks still apply. `{:ok, name, :as_asked | {:instead, why}}`.
  """
  def lead_for(%Thread{} = thread, wanted) do
    current = Server.Channel.thread_lead(thread.id)
    kind = @staff_by_stage[thread.stage]

    seat =
      thread.workspace_id && thread.workspace_id |> Server.Workspaces.bench_all() |> Enum.find(&(&1.name == wanted))

    cond do
      is_nil(current) or is_nil(seat) ->
        {:ok, wanted, :as_asked}

      kind && seat.archetype != kind ->
        {:ok, current, {:instead, "#{wanted} is a #{seat.archetype}; the #{thread.stage} stage is a #{kind}'s"}}

      leading_another?(seat, thread) ->
        {:ok, current, {:instead, "#{wanted} is leading another workline"}}

      true ->
        {:ok, wanted, :as_asked}
    end
  end

  defp leading_another?(%Server.Coworker{agent_id: agent_id}, thread) do
    Repo.exists?(
      from t in Thread,
        where:
          t.agent_id == ^agent_id and t.id != ^thread.id and t.state == "open" and not is_nil(t.stage) and
            t.stage != "landed" and is_nil(t.awaiting)
    )
  end

  @hire_names ~w(averroes beatriz emma ireneo tzinacan ulrikke runeberg nolan pierre zunz)

  # the hire runs on the model its peers of the kind were set to (their workspace policy), so a
  # reviewer moved to another model family stays one when the bench grows
  defp hire_for(thread, kind, peers) do
    taken = MapSet.new(Repo.all(from a in Server.Agent, select: a.name))
    name = Enum.find(@hire_names, &(not MapSet.member?(taken, &1))) || "#{kind}-#{System.unique_integer([:positive])}"
    ws = thread.workspace_id

    case Server.Workspaces.seat(ws, %{name: name, archetype: kind, crew: Server.Shifts.hire_crew(ws)}) do
      {:ok, hired} ->
        with %{model: model} when not is_nil(model) <-
               Enum.find_value(peers, &Server.Workspaces.policy(ws, &1.agent_id)) do
          Server.Workspaces.set_policy(ws, hired.agent_id, %{model: model})
        end

        hand_to(thread, kind, name)

      {:error, why} ->
        restaff_miss(thread, kind, "could not hire a #{kind}: #{inspect(why)}")
    end
  end

  # Already theirs: nothing to hand over, and nothing to announce.
  defp hand_to(thread, kind, name, note \\ nil) do
    if Server.Channel.thread_lead(thread.id) == name do
      thread
    else
      case Server.Channel.assign_lead(thread.id, name) do
        {:ok, restaffed} ->
          close_leaf(restaffed)
          post_brief(restaffed, "#{Server.Trust.leads_line(name, thread.stage)}#{note}")
          restaffed

        {:error, reason} ->
          restaff_miss(thread, kind, inspect(reason))
      end
    end
  end

  # A thread has one window, its lead's: the old lead's must close or the new lead can never be
  # spawned (the builder kept the leaf and did verify's job; the reviewer's brief went nowhere).
  # The brief that follows spawns the new lead, as `Server.Staffing.hand_off/2` does.
  defp close_leaf(%Thread{workspace_id: ws} = thread) when not is_nil(ws) do
    with %{index: index} <- Server.Staffing.leaf_window(thread, "close_leaf"),
         do: Server.Tmux.kill_window(ws, index)
  end

  defp close_leaf(_thread), do: :ok

  defp restaff_miss(thread, "reviewer", why) do
    post_brief(thread, "⚠ review stage could not restaff a reviewer (#{why}) — the current lead still holds it")
    thread
  end

  defp restaff_miss(thread, _kind, _why), do: thread

  # The review gate's approval is the merge: work/<slug> onto main (`Merge`), or — when it can't —
  # the gate stays parked and the thread says why. Only against the real checker unless a test
  # hands its own merger: a stub must never merge in the live repo.
  defp land(%Thread{stage: "review"} = thread, checker, opts) do
    case Keyword.get(opts, :merge, if(checker == Git, do: Server.Workline.Merge)) do
      nil ->
        {:ok, nil}

      merger ->
        repo = Git.root(thread)

        case merger.merge(repo, thread.slug) do
          {:ok, moved} ->
            {:ok, Map.put(moved, :repo, repo)}

          {:error, why} ->
            post_brief(
              thread,
              "⚠ couldn't merge work/#{thread.slug}: #{why} The gate stays parked; approve again once it's fixed."
            )

            {:error, {:merge, why}}
        end
    end
  end

  defp land(_thread, _checker, _opts), do: {:ok, nil}

  # landed: what changed rolls out and the branch goes to GitHub, where it is not merged yet — the
  # thread stays open until GitHub merges the PR (`merged/2`). With no GitHub, the landing is the merge.
  defp finish(thread, %{repo: repo, from: from, to: to} = moved, run) do
    Server.Rollout.after_merge(%{repo: repo, from: from, to: to, thread_id: thread.id})
    publish(thread, repo, "⤵ landed as #{String.slice(to, 0, 7)}", String.slice(to, 0, 7), run, moved[:gated])
  rescue
    e ->
      why = "merged, but its close-out failed (not published to GitHub): #{Exception.message(e)}"
      require(Logger) && Logger.warning("workline #{thread.slug}: #{why}")
      unpublished(thread, "⚠ #{why}")
  end

  @doc """
  Publish a landed workline whose publish failed (`Server.Office.Needs`' `publish_failed`) again: the
  same push and PR its landing tried. `{:ok, pr_url}` | `{:auto_refused, pr_url, why}` | `:none` (no
  origin) | `{:error, why}` — a
  failure is recorded again; a workline whose last publish did not fail is refused.
  """
  def republish(thread, run \\ &System.cmd/3)

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

  # `gated`: the sha the merge queue's gate passed on, posted as tlon/check; a republish has none
  defp publish(thread, repo, landed, ref, run, gated \\ nil) do
    case Server.Workline.Publish.publish(repo, thread.slug, thread.title, run, gated: gated) do
      {:ok, url} = ok ->
        record_publish(thread, 0, url)
        record_landing(thread, "check_passed", landing_check(url, 0, "published"))

        post_brief(
          thread,
          "#{landed}; published as #{url} — the thread closes once GitHub reports it merged"
        )

        ok

      {:auto_refused, url, why} = refused ->
        record_publish(thread, 0, url)
        record_landing(thread, "check_failed", landing_check(url, 1, "merge refused: #{why}"))
        post_brief(thread, "#{landed}; published as #{url}, but GitHub refused to merge it: #{why}")
        refused

      :none ->
        record_publish(thread, 0, "no origin to publish to")
        post_brief(thread, landed)
        merged(thread, ref)
        :none

      {:error, why} = error ->
        unpublished(thread, "#{landed}, but not published to GitHub: #{why}")
        error
    end
  end

  # the failure is recorded for the operator's list (`Server.Office.Needs`' `publish_failed`), and the
  # sheriff is told too, so the work reaches main
  defp unpublished(thread, why) do
    record_publish(thread, 1, why)
    post_brief(thread, why)
    Server.Sheriff.report(thread, "work/#{thread.slug} — #{why}")
  end

  defp record_publish(thread, exit, tail) do
    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: thread.id,
        kind: if(exit == 0, do: "check_passed", else: "check_failed"),
        correlation: publish_correlation(thread),
        detail: %{"cmd" => "publish work/#{thread.slug}", "exit" => exit, "tail" => tail}
      })
  end

  # what the stage's lead should be: the grade and area the ask names; for a review, also not the
  # builder's model and no lower than the builder's grade (roster design §3)
  defp wanted(thread, kind, builder) do
    opening = Server.Channel.opening_operator_message(thread.id)
    text = Enum.join([thread.title, opening && opening.body], "\n")
    base = %{grade: Server.Roster.wanted_grade(text, thread.grade), specialty: Server.Roster.specialty_of(text)}

    if kind == "reviewer" and builder,
      do: Map.merge(base, %{not_model: seat_model(thread.workspace_id, builder), min_grade: builder.grade || "senior"}),
      else: base
  end

  defp seat_model(ws, %Server.Coworker{name: name, archetype: archetype}) do
    entry = Server.Profiles.roster_entry(%{"name" => name, "archetype" => archetype})
    if entry.archetype, do: Server.Profiles.instantiate(entry, ws).model[:model]
  end

  defp shortfall([], _builder, _ws), do: nil

  defp shortfall(short, builder, ws) do
    why =
      Enum.map(short, fn
        :same_model -> "no free reviewer runs another model than the builder's (#{seat_model(ws, builder)})"
        :below_grade -> "no free reviewer is at the builder's grade (#{builder.grade || "senior"})"
      end)

    " — " <> Enum.join(why, "; ") <> ". Say so in review.md's first line."
  end

  # how many times this workline's review has asked for changes (each verdict is recorded evidence)
  defp changes_requested(thread) do
    Repo.aggregate(
      from(e in Server.Event,
        where:
          e.thread_id == ^thread.id and e.kind == "check_failed" and e.correlation == ^"workline:#{thread.slug}:review"
      ),
      :count
    )
  end

  # at review, a change Andrew would see waits on a QA pass since it last entered review — where the
  # bench seats a qa; a bench without one lands it as before
  defp qa_cleared(thread, opts) do
    case qa_owed(thread, opts) do
      nil ->
        :ok

      {seat, _paths} ->
        if Server.Channel.thread_lead(thread.id) == seat.name,
          do: {:error, {:artifact_missing, "QA is yours: " <> qa_playbook(thread)}},
          else:
            {:error,
             {:artifact_missing,
              "QA hasn't passed this user-visible change: #{seat.name} drives it against a scratch release and files what it saw with submit_qa"}}
    end
  end

  defp qa_playbook(thread) do
    """
    drive the changed path as Andrew would, against a scratch release of work/#{thread.slug}: \
    `start_smoke(thread_id: #{thread.id})` has the service build it on its own port and db, smoke it and keep it up \
    (it posts the url here); drive it with `drive_smoke(keys, thread_id: #{thread.id})`, the steps of `office:drive`; \
    `stop_smoke` when done. Your own Bash can run neither: it has no Postgres socket and a network of its own. \
    Never :4040, the live service. Then submit_qa with thread_id: #{thread.id}: pass, or fail with the \
    finding — what you pressed and the screen text you saw.\
    """
  end

  defp qa_owed(%Thread{stage: "review", workspace_id: ws} = thread, opts) when not is_nil(ws) do
    with %Server.Coworker{} = seat <- qa_seat(thread),
         [_ | _] = paths <- Enum.filter(changed_paths(thread, opts), &String.starts_with?(&1, @user_visible)),
         false <- match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:qa")) do
      {seat, paths}
    else
      _ -> nil
    end
  end

  defp qa_owed(_thread, _opts), do: nil

  defp changed_paths(thread, opts) do
    Keyword.get_lazy(opts, :paths, fn ->
      if Keyword.get(opts, :artifacts, Git) == Git, do: Git.changed_paths(thread), else: []
    end)
  end

  # the thread's lead when it is the qa already, else a free one, else any
  defp qa_seat(thread) do
    seats = thread.workspace_id |> Server.Workspaces.bench() |> Enum.filter(&(&1.archetype == "qa"))
    current = Server.Channel.thread_lead(thread.id)

    Enum.find(seats, &(&1.name == current)) || Enum.find(seats, &(not leading_another?(&1, thread))) ||
      List.first(seats)
  end

  defp to_qa(thread, seat, paths) do
    handed = hand_to(thread, "qa", seat.name)

    post_brief(
      handed,
      "🎭 QA: the review approved a change Andrew will see (#{Enum.join(Enum.take(paths, 5), ", ")}). " <>
        String.capitalize(qa_playbook(thread))
    )

    handed
  end

  defp skip_qa(thread, reason) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "qa skipped by the operator",
        exit: 0,
        tail: "skipped by the operator: #{reason}",
        correlation: "workline:#{thread.slug}:qa"
      })

    post_brief(thread, "⚠ QA skipped by the operator: #{reason}")
  end

  # A thread opens with the manager as its lead; a workline is a builder's — a free one, else one
  # hired beside the bench's busy builders (restaff). A bench with no builder to give it to leaves
  # it unled for triage: the manager never keeps it.
  defp unseat_manager(thread) do
    if manager_leads?(thread) do
      restaffed = restaff(thread)

      if manager_leads?(restaffed) do
        close_leaf(restaffed)
        {:ok, unled} = Server.Staff.unassign(restaffed)
        unled
      else
        restaffed
      end
    else
      thread
    end
  end

  defp manager_leads?(thread), do: Server.Channel.manager_on_workline?(thread, Server.Channel.thread_lead(thread.id))

  # back to `to` on the same thread and branch: the stage and its ledger row in one write, the
  # stage's lead staffed and handed `brief`. `allowed` is judged on the row locked FOR UPDATE, the
  # lock the landing reads it under (`Server.Jobs.Land`), so a landing starting at the same instant
  # either sees the move or is seen by `allowed`. `by`, the seat that moved it back, is recorded for
  # the diary; nil when the machine did.
  defp move_back(thread, to, why, brief, allowed, by) do
    fn ->
      locked = Repo.one!(from t in Thread, where: t.id == ^thread.id, lock: "FOR UPDATE")

      case allowed.(locked) do
        :ok ->
          {:ok, back} = locked |> Thread.workline_stage_changeset(%{stage: to, awaiting: nil}) |> Repo.update()

          {:ok, _event} =
            Dossier.record_event(%{
              thread_id: thread.id,
              kind: "stage_advanced",
              correlation: "workline:#{thread.slug}",
              detail: %{"from" => locked.stage, "to" => to, "bounced" => why, "by" => by}
            })

          back

        {:error, refusal} ->
          Repo.rollback(refusal)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, back} ->
        back = restaff(back)
        Server.Bus.broadcast({:workline_advanced, back})
        post_brief(back, brief)
        {:ok, back}

      {:error, refusal} ->
        {:error, refusal}
    end
  end

  defp behind(%Thread{stage: stage}, to) do
    index = &Enum.find_index(@stages, fn s -> s == &1 end)

    if to in ~w(spec plan build) and stage in @stages and index.(to) < index.(stage),
      do: :ok,
      else: {:error, {:not_behind, to}}
  end

  defp may_send_back(thread, to, by) do
    tech = tech_lead(thread)
    lead = Server.Channel.thread_lead(thread.id)

    cond do
      by == operator() or by == tech ->
        :ok

      to == "build" and by == lead ->
        :ok

      to == "build" ->
        {:error,
         {:not_yours, "only ##{thread.id}'s lead (#{lead}), the tech lead or the operator sends it back to build"}}

      true ->
        {:error,
         {:not_yours,
          "back to #{to} is the tech lead's call: say why on the thread and @#{tech || operator()}, who decides"}}
    end
  end

  defp tech_lead(%Thread{workspace_id: nil}), do: nil

  defp tech_lead(%Thread{workspace_id: ws}) do
    ws
    |> Server.Workspaces.bench()
    |> Server.Coworker.lead()
    |> case do
      %{name: name} -> name
      nil -> nil
    end
  end

  defp send_back_brief("build", why, by),
    do:
      "↩ back to build — sent back by #{by}: #{why}. The branch keeps the build and its review: fix what's named, then advance_stage; it comes back through verify and review."

  defp send_back_brief(to, why, by),
    do:
      "↩ back to #{to} — sent back by #{by}: #{why}. The branch keeps the build and review.md: revise #{to}.md to say what changes and what stays, so the build is improved, not redone; then advance_stage."

  # the stage a workline was opened at: its first stage_advanced, the one from nowhere
  defp entry_stage(thread) do
    Repo.one(
      from e in Server.Event,
        where:
          e.thread_id == ^thread.id and e.kind == "stage_advanced" and
            fragment("(?::jsonb ->> 'from') is null", e.detail),
        order_by: [asc: e.id],
        limit: 1,
        select: fragment("?::jsonb ->> 'to'", e.detail)
    ) || "intent"
  end

  defp tied_follow_ups(thread_id) do
    from(t in Server.Ticket,
      join: tt in Server.TicketThread,
      on: tt.ticket_id == t.id,
      where: tt.thread_id == ^thread_id and tt.kind == "relates"
    )
    |> Repo.all()
    |> Enum.filter(&(is_list(&1.labels) and "follow-up" in &1.labels))
  end

  defp movable(%Thread{state: "open", stage: stage}) when stage in ~w(plan build verify review), do: :ok
  defp movable(%Thread{stage: stage}), do: {:error, {:not_movable, stage}}

  defp not_in_flight(thread) do
    queues =
      Repo.all(
        from j in Oban.Job,
          where:
            j.queue in ["verify", "landing"] and j.state in ["available", "scheduled", "executing", "retryable"] and
              fragment("?->>'thread_id'", j.args) == ^to_string(thread.id),
          select: j.queue
      )

    case queues do
      [] ->
        :ok

      [q | _] ->
        {:error,
         {:in_flight, "its #{if q == "verify", do: "verify", else: "landing"} is queued or running; let it finish"}}
    end
  end

  # the review approved the code it read (its verdict's `sha`): code committed after it goes back
  # to build like any other change, through verify and a review of what changed
  defp reviewed_current(%Thread{stage: "review"} = thread) do
    with %{detail: %{"sha" => seen}} when is_binary(seen) <- since_review(thread, "workline:#{thread.slug}:review"),
         now when is_binary(now) <- branch_head(thread),
         {:changed, how} <- compare_code(thread, seen, now) do
      why =
        if how == :conflicts,
          do: "work/#{thread.slug} was rebased onto main with conflicts resolved after its review",
          else: "work/#{thread.slug} has code committed after its review"

      bounce(
        thread,
        why,
        "#{why} (reviewed at #{String.slice(seen, 0, 7)}, now #{String.slice(now, 0, 7)}): it comes back through verify and a review of what changed"
      )
    else
      _ -> :ok
    end
  end

  defp reviewed_current(_thread), do: :ok

  # the newest review verdict's commit, any round: where a returning reviewer last looked
  defp last_reviewed(thread) do
    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:review",
        order_by: [desc: e.id],
        limit: 1,
        select: fragment("(?::jsonb ->> 'sha')", e.detail)
    )
  end

  # any review verdict, even one from before verdicts recorded a sha
  defp reviewed_before?(thread),
    do:
      Repo.exists?(
        from e in Server.Event, where: e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:review"
      )

  # no commits of its own on either side (its code is on main already): the trees decide
  defp same_tree?(root, sha, head, slug),
    do:
      match?(
        {_, 0},
        System.cmd("git", ["-C", root, "diff", "--quiet", sha, head, "--", ".", ":!work/#{slug}"],
          stderr_to_stdout: true
        )
      )

  defp main_ref(root) do
    Enum.find(
      ["origin/main", "main"],
      &match?({_, 0}, System.cmd("git", ["-C", root, "rev-parse", "--verify", "--quiet", &1], stderr_to_stdout: true))
    )
  end

  # `{subject, patch-id}` of each of `ref`'s commits main doesn't have that touches code, oldest first
  defp own_patches(root, base, ref, slug) do
    case System.cmd("git", ["-C", root, "cherry", base, ref], stderr_to_stdout: true) do
      {out, 0} ->
        commits = for "+ " <> c <- String.split(out, "\n", trim: true), do: c
        patches_of(root, slug, commits)

      {out, code} ->
        {:error, {code, String.slice(out, 0, 200)}}
    end
  end

  defp patches_of(_root, _slug, []), do: {:ok, []}

  defp patches_of(root, slug, commits) do
    # pipefail: a git failure is the pipeline's, not hidden behind patch-id's exit
    script = ~s(git -C "$1" show --format='commit %H' "${@:3}" -- . ":!work/$2" | git patch-id --stable)

    with {ids, 0} <-
           System.cmd("bash", ["-o", "pipefail", "-c", script, "bash", root, slug | commits], stderr_to_stdout: true),
         {subjects, 0} <-
           System.cmd("git", ["-C", root, "show", "-s", "--format=%H%x09%s" | commits], stderr_to_stdout: true) do
      id_of =
        Map.new(String.split(ids, "\n", trim: true), &(&1 |> String.split(" ") |> Enum.reverse() |> List.to_tuple()))

      subject_of =
        Map.new(String.split(subjects, "\n", trim: true), &(&1 |> String.split("\t", parts: 2) |> List.to_tuple()))

      {:ok, for(c <- commits, id = id_of[c], do: {subject_of[c], id})}
    else
      {out, code} -> {:error, {code, String.slice(out, 0, 200)}}
    end
  end

  # The branch's own change at `head` against what was judged at `sha`, not their trees: its commits
  # main doesn't already have (`git cherry`, so a commit main took on its own drops out), each by the
  # patch-id of its code (work/<slug>/ left out: the server commits review.md after a verdict). A
  # rebase onto a newer main (the merge queue keeps its rebase across a cut-off gate) is `:same`; the
  # same commits with other patches are `{:changed, :conflicts}`, a resolved rebase; anything else
  # `{:changed, :code}`. A git error is `{:changed, :unreadable}`, and logged.
  defp compare_code(_thread, sha, sha), do: :same

  defp compare_code(thread, sha, head) do
    root = Git.root(thread)

    with base when is_binary(base) <- main_ref(root),
         {:ok, seen} <- own_patches(root, base, sha, thread.slug),
         {:ok, now} <- own_patches(root, base, head, thread.slug) do
      patches_compared(seen, now, fn -> same_tree?(root, sha, head, thread.slug) end)
    else
      why ->
        require(Logger) && Logger.warning("workline #{thread.slug}: can't compare #{sha} with #{head}: #{inspect(why)}")
        {:changed, :unreadable}
    end
  end

  # review.md stays on the branch across rounds: back at review after a bounce, the file is the last
  # round's, so only a verdict since the workline re-entered review is this round's review
  defp this_round({:ok, _} = ok, %Thread{stage: "review"} = thread) do
    if is_nil(since_review(thread, "workline:#{thread.slug}:review")) and reviewed_before?(thread),
      do: {:error, "work/#{thread.slug}/review.md is the last round's — submit_review this round's verdict"},
      else: ok
  end

  defp this_round(result, _thread), do: result

  # `{subject, patch-id}` lists: the same patches are the same change; the same commits with other
  # patches, a rebase whose conflicts were resolved. No commits of its own on either side (its code
  # is on main already): `same_tree?` decides.
  defp patches_compared([], [], same_tree?), do: if(same_tree?.(), do: :same, else: {:changed, :code})

  defp patches_compared(seen, now, _same_tree?) do
    cond do
      Enum.map(seen, &elem(&1, 1)) == Enum.map(now, &elem(&1, 1)) -> :same
      Enum.map(seen, &elem(&1, 0)) == Enum.map(now, &elem(&1, 0)) -> {:changed, :conflicts}
      true -> {:changed, :code}
    end
  end

  # the gate passed: flip it to merged unless it moved off review while the gate ran
  defp landed(thread, moved, run) do
    case flip(thread) do
      {:ok, flipped} ->
        finish(flipped, moved, run)
        Server.Jobs.enqueue(Server.Jobs.Retro.new(%{thread_id: flipped.id}))
        {:ok, flipped}

      {:error, {:moved, now}} ->
        post_brief(
          thread,
          "⚠ the merge queue's gate passed, but the workline moved to #{now} while it ran — nothing landed."
        )

        {:ok, Repo.get!(Thread, thread.id)}
    end
  end

  defp still_open(%Thread{state: "closed"}), do: {:error, :closed}
  defp still_open(_thread), do: :ok

  defp flipped_after(flipped) do
    # Restaff BEFORE broadcasting: subscribers acting on the advance must never observe the
    # last stage's worker still leading this one.
    flipped = restaff(flipped)
    Server.Bus.broadcast({:workline_advanced, flipped})

    post_brief(
      flipped,
      Brief.stage_message(flipped, last_reviewed: flipped.stage == "review" && last_reviewed(flipped))
    )

    if flipped.stage == "verify",
      do: Server.Jobs.enqueue(Server.Jobs.Verify.new(%{thread_id: flipped.id, slug: flipped.slug}))

    {:ok, flipped}
  end

  defp approved_at?(thread, sha) do
    case since_review(thread, "workline:#{thread.slug}:review") do
      %{kind: "check_passed", detail: detail} -> detail["sha"] == sha
      _ -> false
    end
  end

  defp record_verdict(thread, verdict, author, sha, opts) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "review verdict by #{author}",
        exit: if(verdict == "approve", do: 0, else: 1),
        tail: verdict,
        correlation: "workline:#{thread.slug}:review",
        sha: sha
      })

    # the verdict ends the reviewer's session: a review is a throwaway session, briefed fresh each round
    Server.Staffing.end_review(thread)

    outcome =
      if verdict == "request_changes" do
        bounced =
          bounce(
            thread,
            "the review requested changes",
            "the review requested changes: read work/#{thread.slug}/review.md, fix them test-first",
            author
          )

        if changes_requested(thread) >= 2,
          do: escalate(Repo.get!(Thread, thread.id), "the review asked for changes twice")

        bounced
      else
        Server.Jobs.enqueue(Server.Jobs.Grade.new(%{thread_id: thread.id}))

        case qa_owed(thread, opts) do
          nil -> park_approved(thread, opts)
          {seat, paths} -> {:ok, to_qa(thread, seat, paths)}
        end
      end

    {:ok, _} = follow_ups(thread, author, Keyword.get(opts, :follow_ups, []), :review)
    outcome
  end

  # The verdict ended the reviewer's session, so nobody is left to call advance_stage: the approval
  # parks the gate itself (#686) — on the operator, or straight into the queue under a standing
  # approval. An advance refused here (review.md not committed, a test without a repo) leaves the
  # verdict standing: the refusal is in the ledger as the artifact check.
  defp park_approved(thread, opts) do
    case advance(Repo.get!(Thread, thread.id), opts) do
      {:awaiting, parked} -> {:ok, parked}
      {:ok, moved} -> {:ok, moved}
      {:error, _} -> {:ok, thread}
    end
  end

  defp by_hand(thread, url) do
    record_publish(thread, 0, url)
    record_landing(thread, "check_passed", landing_check(url, 0, "opened by hand"))
    post_brief(thread, "its PR opened by hand: #{url} — the thread closes when GitHub merges it")
    {:ok, thread}
  end

  defp land_again(thread, url, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate(thread, &1, &2) end)
    run = Keyword.get(opts, :run, &System.cmd/3)
    auto? = opts[:auto] == true
    repo = Git.root(thread)

    case merger.merge(repo, thread.slug, gate: gate) do
      {:ok, %{to: sha}} ->
        merge_again(thread, url, repo, sha, run)

      {:error, {:interrupted, why}} = cut ->
        if opts[:last],
          do:
            record_landing(thread, "check_failed", landing_check(url, 1, "the merge queue's gate was cut off: #{why}"))

        cut

      {:error, why} when auto? ->
        record_landing(thread, "check_failed", landing_check(url, 1, "the merge queue couldn't land it again: #{why}"))
        post_brief(thread, "⚠ the merge queue couldn't land it again: #{why} — it waits on the operator")
        {:error, why}

      {:error, why} ->
        refuse_again(thread, url, repo, why, run)
    end
  end

  defp merge_again(thread, url, repo, sha, run) do
    branch = "work/#{thread.slug}"

    with :ok <- Server.Workline.Publish.fetch_branch(repo, branch, run),
         :ok <- Server.Workline.Publish.push_branch(repo, branch, run),
         Server.Workline.Publish.post_check(repo, sha, run),
         how when how in [:merged, :auto] <- Server.Workline.Publish.merge_at(repo, url, sha, branch, run) do
      said = if how == :merged, do: "merged", else: "auto-merge armed at that head"
      detail = landing_check(url, 0, "gated at #{String.slice(sha, 0, 7)}; #{said}")
      # GitHub merges an armed head itself: KeepUp requeueing it again would gate it for nothing
      detail = if how == :auto, do: Map.put(detail, "requeued_head", sha), else: detail
      record_landing(thread, "check_passed", detail)
      post_brief(thread, "⤵ landed again as #{String.slice(sha, 0, 7)}, gated on main; #{url}: #{said}")
      {:ok, thread}
    else
      {:error, why} ->
        record_landing(thread, "check_failed", landing_check(url, 1, "merge refused: #{why}"))
        post_brief(thread, "⚠ gated green at #{String.slice(sha, 0, 7)}, but GitHub refused it: #{why}")
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
        record_landing(thread, "check_failed", landing_check(url, 1, "#{why}; its PR wouldn't close: #{out}"))
        {:error, why}
    end
  end

  defp requeue(thread, url, why, head) do
    with {:ok, _job} <-
           Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id, reland: true, auto: true})) do
      detail = Map.put(landing_check(url, 0, "#{why}: back in the merge queue on its own"), "requeued_head", head)
      record_landing(thread, "check_passed", detail)
      post_brief(thread, "⧗ #{why} — back in the merge queue on its own: #{url} lands once rebased and gated")
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

  defp operator, do: Server.OperatorConfig.operator()

  defp owed_artifact(thread, checker),
    do: thread |> checker.check(Map.fetch!(@owed, thread.stage)) |> this_round(thread)

  defp follow_up_title(text), do: text |> String.split("\n", parts: 2) |> hd() |> String.trim()

  defp rideable?(%Thread{stage: "review", awaiting: nil, state: "open"} = t), do: reviewed_current(t) == :ok
  defp rideable?(_thread), do: false

  defp ride([{lead, _} = first | rest], repo, merger, opts) do
    run = Keyword.get(opts, :run, &System.cmd/3)

    case ride_on(first, repo, merger, run) do
      {:cont, :ok} ->
        post_brief(
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
end
