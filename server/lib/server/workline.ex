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
  alias Server.Workline.Landing
  alias Server.Workline.Review
  alias Server.Workline.Scribe
  alias Server.Workline.SendBack

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
    Map.has_key?(@owed, stage) or raise "stage #{stage} has no owed artifact in @owed"
  end

  for stage <- @gated do
    stage in @stages or raise "gated stage #{stage} is not in @stages"
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

  An optional `:lead` (a manager's pick) leads when they are of the stage's kind (intent takes anyone
  on the bench) and lead no other live workline; else the stage's own pick leads and the thread says why.
  """
  def open(attrs) do
    {wanted, attrs} = Map.pop(attrs, :lead)
    stage = Map.get(attrs, :stage, "intent")

    if stage in @openable do
      attrs =
        attrs
        |> Map.put(:stage, stage)
        |> Map.put_new_lazy(:workspace_id, &Server.Bootstrap.default_workspace_id/0)

      with {:ok, thread} <-
             attrs |> Thread.workline_changeset() |> Repo.insert() |> Server.Bus.announce(:thread_opened) do
        # staffed first, so the brief — the wake from the entry stage — reaches its lead
        thread = staff_opened(thread, wanted)
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

  defdelegate landing(thread_id, fun), to: Landing

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
      if landed, do: finish(flipped, landed, Keyword.get(opts, :run, &Server.Cmd.run/3))
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

  def queue(thread, why, by) do
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
    case Server.Git.cmd(Git.root(thread), ["rev-parse", "--verify", "--quiet", "work/#{thread.slug}^{commit}"]) do
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

  defdelegate requeue_stranded, to: Landing

  defdelegate land_train(lead, others, opts \\ []), to: Landing

  defdelegate land_queued(thread, opts \\ []), to: Landing

  defdelegate reland(thread, why, todo \\ nil), to: Landing

  defdelegate merged(thread, ref), to: Landing

  defdelegate waiting_on_github, to: Landing

  defdelegate landing_blocked(thread, why), to: Landing

  defdelegate rebase_landing(thread), to: Landing

  defdelegate requeue_blocked(thread, why, head), to: Landing

  defdelegate reland_queued(thread, opts \\ []), to: Landing

  defdelegate reland_landing(thread, run \\ &Server.Cmd.run/3), to: Landing

  def landing_check(url, exit, tail),
    do: %{"cmd" => "GitHub merge of #{url}", "exit" => exit, "url" => url, "tail" => tail}

  def record_landing(thread, kind, detail) do
    {:ok, _} =
      Dossier.record_event(%{
        thread_id: thread.id,
        kind: kind,
        correlation: "workline:#{thread.slug}:landing",
        detail: detail
      })
  end

  defdelegate landed_since(since), to: Landing

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

  defdelegate review_verdict(thread, verdict, author, opts \\ []), to: Review

  defdelegate self_review(thread, author), to: Review

  defdelegate qa_verdict(thread, verdict, author, report, opts \\ []), to: Review

  defdelegate graded(thread, opts \\ []), to: Review

  # A standing approval: the operator's `auto_land_risk` — a reviewed-and-approved workline whose
  # risk grade has no axis over it (and no limit hit, no decision left open) lands without them,
  # through the same gated queue. Off unless set; a test hands the threshold outright.
  # A builder with a good enough record has earned a step more of it (`Server.Trust`).
  def auto_land?(thread, checker, opts) do
    max = Keyword.get_lazy(opts, :auto_land_risk, fn -> if checker == Git, do: auto_land_risk() end)

    is_integer(max) and review_approved?(thread) and
      Grade.allows?(grade(thread), elem(Server.Trust.allowance(thread, max), 0)) and
      qa_cleared(thread, opts) == :ok
  end

  def auto_land_note(thread, opts) do
    {max, earned} = Server.Trust.allowance(thread, Keyword.get_lazy(opts, :auto_land_risk, &auto_land_risk/0))

    by =
      if earned,
        do:
          ": one over your setting, earned by #{earned.name}#{if earned.model, do: " on #{earned.model}"}, who landed #{earned.first_time} of their last #{earned.led} builds first time",
        else: ""

    "auto-approved by your standing approval (reviewed; #{Grade.line(grade(thread))}, none over #{max}#{by})"
  end

  defp auto_land_risk, do: Server.OperatorConfig.setting("auto_land_risk")

  defdelegate grade_limits(thread), to: Review

  defdelegate limit_hit?(thread), to: Review

  # the newest grade since the workline last entered review: nil if none, or the grader failed
  def grade(thread) do
    case since_review(thread, "workline:#{thread.slug}:grade") do
      %{kind: "check_passed", detail: grade} -> grade
      _ -> nil
    end
  end

  defp review_approved?(thread),
    do: match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:review"))

  # the newest event of `correlation` since the workline last entered review
  def since_review(thread, correlation) do
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

  def bounce(thread, why, headline, by \\ nil) do
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

  defdelegate send_back(thread, to, why, by, opts \\ []), to: SendBack

  defdelegate follow_ups(thread, author, items, door \\ :review), to: Review

  defdelegate follow_up_items(items), to: Review

  defdelegate release_follow_ups(thread), to: Review

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
  def flip(thread) do
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
  def post_brief(thread, body) do
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
  def restaff(%Thread{stage: "intent", workspace_id: ws} = thread) when not is_nil(ws) do
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

  def restaff(%Thread{stage: stage} = thread) do
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

        candidates =
          Enum.map(
            free,
            &with_trust(%{coworker: &1, model: seat_model(thread.workspace_id, &1)})
          )

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
         candidates = Enum.map(above, &with_trust(%{coworker: &1, model: nil})),
         {%Server.Coworker{name: name}, _} <-
           Server.Roster.pick(candidates, %{grade: "senior", specialty: junior.specialty}),
         {:ok, _} <- Server.Channel.assign_lead(thread.id, name) do
      close_leaf(thread)

      landed =
        case Enum.find(candidates, &(&1.coworker.name == name)) do
          %{trust: %{led: led, first_time: first}} when led > 0 ->
            " (landed #{first} of their last #{led} builds first time)"

          _ ->
            ""
        end

      {:ok, _} =
        Server.Channel.post(%{
          thread_id: thread.id,
          author: "tlon",
          body: "↑ #{name} takes this from #{current}#{landed}: #{why}. Pick it up from the brief.",
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

    candidates =
      Enum.map(
        if(free == [], do: of_kind, else: free),
        &with_trust(%{coworker: &1, model: nil})
      )

    case Server.Roster.pick(candidates, want) do
      {%Server.Coworker{name: name}, _} -> name
      nil -> nil
    end
  end

  def leading_another?(%Server.Coworker{agent_id: agent_id}, thread) do
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
  def hand_to(thread, kind, name, note \\ nil) do
    if Server.Channel.thread_lead(thread.id) == name do
      thread
    else
      case Server.Channel.assign_lead(thread.id, name) do
        {:ok, restaffed} ->
          close_leaf(restaffed)
          model = model_label(thread.workspace_id, name)
          post_brief(restaffed, "#{Server.Trust.leads_line(name, thread.stage, model)}#{note}")
          restaffed

        {:error, reason} ->
          restaff_miss(thread, kind, inspect(reason))
      end
    end
  end

  # A thread has one window, its lead's: the old lead's must close or the new lead can never be
  # spawned (the builder kept the leaf and did verify's job; the reviewer's brief went nowhere).
  # The brief that follows spawns the new lead, as `Server.Staffing.hand_off/2` does.
  def close_leaf(%Thread{workspace_id: ws} = thread) when not is_nil(ws) do
    with %{index: index} <- Server.Staffing.leaf_window(thread, "close_leaf"),
         do: Server.Tmux.kill_window(ws, index)
  end

  def close_leaf(_thread), do: :ok

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

          {:error, {:interrupted, why}} ->
            could_not_merge(thread, why)

          {:error, why} ->
            could_not_merge(thread, why)
        end
    end
  end

  defp land(_thread, _checker, _opts), do: {:ok, nil}

  defp could_not_merge(thread, why) do
    post_brief(
      thread,
      "⚠ couldn't merge work/#{thread.slug}: #{why} The gate stays parked; approve again once it's fixed."
    )

    {:error, {:merge, why}}
  end

  # landed: what changed rolls out and the branch goes to GitHub, where it is not merged yet — the
  # thread stays open until GitHub merges the PR (`merged/2`). With no GitHub, the landing is the merge.
  def finish(thread, %{repo: repo, from: from, to: to} = moved, run) do
    Server.Rollout.after_merge(%{repo: repo, from: from, to: to, thread_id: thread.id})
    publish(thread, repo, "⤵ landed as #{String.slice(to, 0, 7)}", String.slice(to, 0, 7), run, moved[:gated])
  rescue
    e ->
      why = "merged, but its close-out failed (not published to GitHub): #{Exception.message(e)}"
      require(Logger) && Logger.warning("workline #{thread.slug}: #{why}")
      unpublished(thread, "⚠ #{why}")
  end

  defdelegate republish(thread, run \\ &Server.Cmd.run/3), to: Landing

  defdelegate published_by_hand(thread, url), to: Landing

  defdelegate publish_correlation(thread), to: Landing

  # `gated`: the sha the merge queue's gate passed on, posted as tlon/check; a republish has none
  def publish(thread, repo, landed, ref, run, gated \\ nil) do
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
  def unpublished(thread, why) do
    record_publish(thread, 1, why)
    post_brief(thread, why)
    Server.Sheriff.report(thread, "work/#{thread.slug} — #{why}")
  end

  def record_publish(thread, exit, tail) do
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

  # at review, a change Andrew would see waits on a QA pass since it last entered review — where the
  # bench seats a qa; a bench without one lands it as before
  def qa_cleared(thread, opts) do
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

  def qa_owed(%Thread{stage: "review", workspace_id: ws} = thread, opts) when not is_nil(ws) do
    with %Server.Coworker{} = seat <- qa_seat(thread),
         [_ | _] = paths <- Enum.filter(changed_paths(thread, opts), &String.starts_with?(&1, @user_visible)),
         false <- match?(%{kind: "check_passed"}, since_review(thread, "workline:#{thread.slug}:qa")) do
      {seat, paths}
    else
      _ -> nil
    end
  end

  def qa_owed(_thread, _opts), do: nil

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

  def to_qa(thread, seat, paths) do
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
  def move_back(thread, to, why, brief, allowed, by) do
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

  # the stage a workline was opened at, read from its earliest stage_advanced: the one from nowhere
  # (a promotion's) names it in `to`; otherwise the first advance left it, so it is that one's
  # `from`. Only `promote/1` writes an opening event — `open/1` at any stage writes none — so a
  # workline that never moved was opened where it stands.
  defp entry_stage(thread) do
    Repo.one(
      from e in Server.Event,
        where: e.thread_id == ^thread.id and e.kind == "stage_advanced",
        order_by: [asc: e.id],
        limit: 1,
        select: fragment("coalesce(?::jsonb ->> 'from', ?::jsonb ->> 'to')", e.detail, e.detail)
    ) || thread.stage
  end

  # the review approved the code it read (its verdict's `sha`): code committed after it goes back
  # to build like any other change, through verify and a review of what changed
  def reviewed_current(%Thread{stage: "review"} = thread) do
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

  def reviewed_current(_thread), do: :ok

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
    do: match?({_, 0}, Server.Git.cmd(root, ["diff", "--quiet", sha, head, "--", ".", ":!work/#{slug}"]))

  def main_ref(root) do
    Enum.find(
      ["origin/main", "main"],
      &match?({_, 0}, Server.Git.cmd(root, ["rev-parse", "--verify", "--quiet", &1]))
    )
  end

  # `{subject, patch-id}` of each of `ref`'s commits main doesn't have that touches code, oldest first
  defp own_patches(root, base, ref, slug) do
    case Server.Git.cmd(root, ["cherry", base, ref]) do
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
           Server.Cmd.run("bash", ["-o", "pipefail", "-c", script, "bash", root, slug | commits],
             stderr_to_stdout: true
           ),
         {subjects, 0} <-
           Server.Git.cmd(root, ["show", "-s", "--format=%H%x09%s" | commits]) do
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
  def compare_code(_thread, sha, sha), do: :same

  def compare_code(thread, sha, head) do
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

  def operator, do: Server.OperatorConfig.operator()

  defp owed_artifact(thread, checker),
    do: thread |> checker.check(Map.fetch!(@owed, thread.stage)) |> this_round(thread)

  # A manager's named lead is the one pick when it fits (`unfit/2`); else the stage's own pick leads
  # and the thread says why — one seat either way.
  defp staff_opened(thread, nil), do: restaff(thread)

  defp staff_opened(thread, wanted) do
    seat =
      thread.workspace_id && thread.workspace_id |> Server.Workspaces.bench_all() |> Enum.find(&(&1.name == wanted))

    case seat && unfit(thread, seat) do
      why when is_binary(why) ->
        staffed = restaff(thread)

        case Server.Channel.thread_lead(staffed.id) do
          nil ->
            hand_to(staffed, @staff_by_stage[thread.stage] || "lead", wanted)

          lead ->
            post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
            staffed
        end

      _ ->
        hand_to(thread, @staff_by_stage[thread.stage] || "lead", wanted)
    end
  end

  # why `seat` cannot lead `thread`, or nil
  defp unfit(thread, seat) do
    kind = @staff_by_stage[thread.stage]

    cond do
      kind && seat.archetype != kind -> "#{seat.name} is a #{seat.archetype}; the #{thread.stage} stage is a #{kind}'s"
      leading_another?(seat, thread) -> "#{seat.name} is leading another workline"
      true -> nil
    end
  end

  # trust only breaks ties, so a lookup that fails leaves the candidate neutral (no `trust` key)
  # instead of dropping the handoff
  def with_trust(%{coworker: %{name: name}} = candidate) do
    Map.put(candidate, :trust, Application.get_env(:server, :trust_record, &Server.Trust.record/1).(name))
  rescue
    e ->
      Logger.warning("trust record for #{name} failed, picking without it: #{Exception.message(e)}")
      candidate
  end

  # the leads line names the model when it can; a lookup that raises posts the line without it
  # rather than leaving the new lead unannounced
  defp model_label(workspace_id, name) do
    Application.get_env(:server, :model_label, &Server.Profiles.model_label/2).(workspace_id, name)
  rescue
    e ->
      Logger.warning("model label for #{name} failed, posting the leads line without it: #{Exception.message(e)}")
      nil
  end
end
