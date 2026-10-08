defmodule Server.Workline do
  @moduledoc """
  The workline stage machine (worklines slice 1, design:
  `docs/plans/2026-08-27-ai-native-sdlc-workline-design.md`). A workline is a thread paired
  with a git folder `work/<slug>/`; its thread carries the stage:

      intent → spec → plan → build → verify → review → merged

  `advance/2` is the single mutation point and carries the invariant: NO advance without the
  stage's owed artifact (checked through the `Server.Workline.Artifacts` behaviour, recorded
  as a CHECK either way, correlation `workline:<slug>:artifact`). Gated transitions —
  spec→plan, review→merged, and a machine-born intent→spec — park in `awaiting: "andrew"`
  instead of flipping; `approve/1` is the operator's completion verb. A reviewed change Andrew
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

  @stages ~w(intent spec plan build verify review merged)
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
  @openable @stages -- ["merged"]

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

    with :ok <- advanceable(thread, checker),
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

    with true <- line =~ ~r/approve/i and not (line =~ ~r/request.?changes/i),
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
  """
  def approve(thread, opts \\ [])

  def approve(%Thread{} = thread, opts) do
    reason = opts |> Keyword.get(:skip_qa) |> to_string() |> String.trim()

    cond do
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
         :ok <- qa_cleared(thread, opts) do
      if queue?(thread, checker, opts),
        do: queue(thread, "approved", thread.awaiting || "andrew"),
        else: approve_now(thread, checker, opts)
    end
  end

  defp approve_now(thread, checker, opts) do
    with {:ok, landed} <- land(thread, checker, opts),
         {:ok, cleared} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         {:ok, flipped} <- flip(cleared) do
      if landed, do: finish(flipped, landed)
      {:ok, flipped}
    end
  end

  # The review gate's approval joins the merge queue (`Server.Jobs.Land`, one landing at a time,
  # each rebased onto main and gated there) — against the real repo; a test's stub merger lands
  # inline, and `land: :queue | :now` says so outright.
  defp queue?(%Thread{stage: "review"}, checker, opts) do
    Keyword.get(opts, :land, if(checker == Git and not Keyword.has_key?(opts, :merge), do: :queue, else: :now)) ==
      :queue
  end

  defp queue?(_thread, _checker, _opts), do: false

  defp queue(thread, why, by) do
    with {:ok, queued} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         {:ok, _job} <- Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id})) do
      record_approval(queued, by)

      post_brief(
        queued,
        "⧗ #{why} — in the merge queue: it lands once rebased onto main and green there, one landing at a time"
      )

      {:ok, queued}
    else
      {:error, why} ->
        {:ok, _} = thread |> Thread.workline_stage_changeset(%{awaiting: thread.awaiting}) |> Repo.update()
        {:error, {:queue, why}}
    end
  end

  # what was approved is the branch at that commit: a later push needs approving again
  defp record_approval(thread, by) do
    Dossier.record_event(%{
      thread_id: thread.id,
      kind: "check_passed",
      correlation: "workline:#{thread.slug}:approval",
      detail: %{"cmd" => "approved by #{by}", "exit" => 0, "by" => by, "sha" => branch_head(thread)}
    })
  end

  @doc """
  The approval that still stands on a workline: the newest one recorded (`%{"by", "sha"}`, who
  approved it into the merge queue and the commit `work/<slug>` was at), while the branch's code is
  what it was then (its own docs, `work/<slug>/`, may have moved); nil once the code has changed,
  or when none was recorded.
  """
  def approval(%Thread{} = thread) do
    correlation = "workline:#{thread.slug}:approval"

    newest =
      Repo.one(
        from e in Server.Event,
          where: e.thread_id == ^thread.id and e.correlation == ^correlation,
          order_by: [desc: e.id],
          limit: 1,
          select: e.detail
      )

    with %{"sha" => sha} = detail when is_binary(sha) <- newest,
         head when is_binary(head) <- branch_head(thread),
         true <- same_code?(thread, sha, head),
         do: Map.take(detail, ["by", "sha"]),
         else: (_ -> nil)
  end

  # the server commits the workline's own docs (a review verdict) onto the branch after an approval;
  # only a change outside work/<slug>/ is a change to what was approved
  defp same_code?(_thread, sha, sha), do: true

  defp same_code?(thread, sha, head) do
    match?(
      {_, 0},
      System.cmd("git", ["-C", Git.root(thread), "diff", "--quiet", sha, head, "--", ".", ":!work/#{thread.slug}"],
        stderr_to_stdout: true
      )
    )
  end

  defp branch_head(thread) do
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

    case merger.merge(repo, thread.slug, gate: gate) do
      {:ok, moved} ->
        {:ok, flipped} = flip(thread)
        finish(flipped, Map.put(moved, :repo, repo))
        {:ok, flipped}

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
  verify, review and the merge queue. Anything not `merged` is left as it is.
  """
  def reland(%Thread{stage: "merged"} = thread, why) do
    Server.Channel.reopen_if_closed(thread.id)
    Server.Tickets.undone_for(thread.id)

    bounce(
      Repo.get!(Thread, thread.id),
      why,
      "#{why}: main moved under it after it landed. Rebase work/#{thread.slug} onto origin/main, resolve it, test"
    )
  end

  def reland(thread, _why), do: {:ok, thread}

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
  handed to the qa seat. `opts` as `advance/2`'s, and `paths:` the changed paths (tests).
  """
  def review_verdict(thread, verdict, author, opts \\ [])

  def review_verdict(%Thread{stage: "review"} = thread, verdict, author, opts)
      when verdict in ~w(approve request_changes) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "review verdict by #{author}",
        exit: if(verdict == "approve", do: 0, else: 1),
        tail: verdict,
        correlation: "workline:#{thread.slug}:review"
      })

    if verdict == "request_changes" do
      bounced =
        bounce(
          thread,
          "the review requested changes",
          "the review requested changes: read work/#{thread.slug}/review.md, fix them test-first"
        )

      if changes_requested(thread) >= 2,
        do: escalate(Repo.get!(Thread, thread.id), "the review asked for changes twice")

      bounced
    else
      Server.Jobs.enqueue(Server.Jobs.Grade.new(%{thread_id: thread.id}))

      case qa_owed(thread, opts) do
        nil -> {:ok, thread}
        {seat, paths} -> {:ok, to_qa(thread, seat, paths)}
      end
    end
  end

  def review_verdict(%Thread{stage: "review"}, verdict, _author, _opts), do: {:error, {:bad_verdict, verdict}}
  def review_verdict(%Thread{stage: stage}, _verdict, _author, _opts), do: {:error, {:not_in_review, stage}}

  @doc """
  The qa seat's verdict on a reviewed change it drove (`submit_qa`): `"pass"` or `"fail"`, its report
  (what it pressed and the screen text it saw) recorded as evidence (`workline:<slug>:qa`). A fail
  sends it back to build with the finding, as a review requesting changes does; a pass advances it
  to the merge gate. `opts` as `advance/2`'s.
  """
  def qa_verdict(thread, verdict, author, report, opts \\ [])

  def qa_verdict(%Thread{stage: "review"} = thread, verdict, author, report, opts) when verdict in ~w(pass fail) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: thread.id,
        cmd: "qa by #{author}",
        exit: if(verdict == "pass", do: 0, else: 1),
        tail: report,
        correlation: "workline:#{thread.slug}:qa"
      })

    if verdict == "fail" do
      bounce(thread, "QA found a problem", "QA (#{author}) drove it and found:\n\n#{report}\n\nFix it test-first")
    else
      post_brief(thread, "✓ QA passed (#{author}):\n\n#{report}")
      advance(Repo.get!(Thread, thread.id), opts)
    end
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

    if thread.stage == "review" and thread.awaiting == "andrew" and auto_land?(thread, checker, opts),
      do: queue(thread, auto_land_note(thread, opts), "auto_land_risk"),
      else: {:ok, thread}
  end

  # A standing approval: the operator's `auto_land_risk` — a reviewed-and-approved workline whose
  # risk grade has no axis over it (and no limit hit, no decision left open) lands without them,
  # through the same gated queue. Off unless set; a test hands the threshold outright.
  defp auto_land?(thread, checker, opts) do
    max = Keyword.get_lazy(opts, :auto_land_risk, fn -> if checker == Git, do: auto_land_risk() end)

    is_integer(max) and review_approved?(thread) and Grade.allows?(grade(thread), max) and
      qa_cleared(thread, opts) == :ok
  end

  defp auto_land_note(thread, opts),
    do:
      "auto-approved by your standing approval (reviewed; #{Grade.line(grade(thread))}, none over #{Keyword.get_lazy(opts, :auto_land_risk, &auto_land_risk/0)})"

  defp auto_land_risk, do: Server.OperatorConfig.setting("auto_land_risk")

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

  # back to build: the stage and its ledger row in one write, the builder restaffed and told why
  defp bounce(thread, why, headline) do
    {:ok, back} =
      Repo.transaction(fn ->
        {:ok, back} = thread |> Thread.workline_stage_changeset(%{stage: "build", awaiting: nil}) |> Repo.update()

        {:ok, _event} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "stage_advanced",
            correlation: "workline:#{thread.slug}",
            detail: %{"from" => thread.stage, "to" => "build", "bounced" => why}
          })

        back
      end)

    back = restaff(back)
    Server.Bus.broadcast({:workline_advanced, back})

    post_brief(back, "↩ back to build — #{headline}, then advance_stage; it comes back through verify and review.")
    {:error, {:bounced, why}}
  end

  @doc """
  The Maintain back-edge's verb: open a MACHINE-BORN workline already parked at the intent
  gate, breach evidence as the opening message. Nothing advances until the operator
  approves — the monitor acts with no human in the invocation path, yet never unsupervised.
  """
  def flag(attrs, evidence) do
    with {:ok, thread} <- open(Map.put(attrs, :born, "machine")) do
      post_brief(thread, evidence)
      {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
      Server.Bus.broadcast({:workline_gated, parked})
      post_brief(parked, Brief.gate_message(parked))
      {:ok, parked}
    end
  end

  defp advanceable(%Thread{stage: nil}, _checker), do: {:error, :not_a_workline}
  defp advanceable(%Thread{stage: "merged"}, _checker), do: {:error, :terminal}

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

    case checker.check(thread, requirement) do
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

  defp park(thread, checker, opts) do
    if thread.stage == "review" and auto_land?(thread, checker, opts),
      do: queue(thread, auto_land_note(thread, opts), "auto_land_risk"),
      else: park_on_operator(thread, checker)
  end

  defp park_on_operator(thread, checker) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
    Server.Bus.broadcast({:workline_gated, parked})
    proof = if parked.stage == "review", do: proof(parked, artifacts: checker)
    post_brief(parked, Brief.gate_message(parked, proof))
    {:awaiting, parked}
  end

  @doc """
  The proof a workline carries into its merge gate, read now from git and the event log: each
  stage's owed artifact up to the current one in the checker's words (verify's is `checks`), the
  newest verify check per command with its measured exit (five, newest first), and the branch's
  diff against HEAD. `%{artifacts: [{stage, {:ok | :error, why}}], checks: [%{cmd, exit}], diff:
  {:ok | :error, text}}`. `opts[:artifacts]` swaps the checker.
  """
  def proof(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Git)
    upto = Enum.take(@stages, Enum.find_index(@stages, &(&1 == thread.stage)) + 1)

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

  # One transaction: the stage flip and its ledger row commit together or not at all.
  defp flip(thread) do
    to = next(thread.stage)

    {:ok, flipped} =
      Repo.transaction(fn ->
        {:ok, flipped} = thread |> Thread.workline_stage_changeset(%{stage: to, awaiting: nil}) |> Repo.update()

        {:ok, _event} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "stage_advanced",
            correlation: "workline:#{thread.slug}",
            detail: %{"from" => thread.stage, "to" => to}
          })

        flipped
      end)

    # Restaff BEFORE broadcasting: subscribers acting on the advance must never observe the
    # last stage's worker still leading this one.
    flipped = restaff(flipped)
    Server.Bus.broadcast({:workline_advanced, flipped})
    post_brief(flipped, Brief.stage_message(flipped))

    if flipped.stage == "verify",
      do: Server.Jobs.enqueue(Server.Jobs.Verify.new(%{thread_id: flipped.id, slug: flipped.slug}))

    {:ok, flipped}
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
  def owed_status(%Thread{stage: "merged"}, _opts), do: :none

  def owed_status(%Thread{} = thread, opts) do
    checker = Keyword.get(opts, :artifacts, Git)

    with :ok <- verified_artifact(thread, checker),
         :ok <- qa_cleared(thread, opts) do
      {:ok, "#{thread.stage} artifact committed"}
    else
      {:error, {:artifact_missing, why}} -> {:error, why}
    end
  end

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
        builder = Enum.find(bench, &(&1.name == current))
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

    with %Server.Coworker{grade: "junior", archetype: kind} = junior <- Enum.find(bench, &(&1.name == current)),
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
  asked. `{:ok, name, :as_asked | {:instead, why}}`.
  """
  def lead_for(%Thread{} = thread, wanted) do
    current = Server.Channel.thread_lead(thread.id)
    kind = @staff_by_stage[thread.stage]
    seat = thread.workspace_id && thread.workspace_id |> Server.Workspaces.bench() |> Enum.find(&(&1.name == wanted))

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
            t.stage != "merged" and is_nil(t.awaiting)
    )
  end

  @hire_names ~w(averroes beatriz emma ireneo tzinacan ulrikke runeberg nolan pierre zunz)

  # the hire runs on the model its peers of the kind were set to (their workspace policy), so a
  # reviewer moved to another model family stays one when the bench grows
  defp hire_for(thread, kind, peers) do
    taken = MapSet.new(Repo.all(from a in Server.Agent, select: a.name))
    name = Enum.find(@hire_names, &(not MapSet.member?(taken, &1))) || "#{kind}-#{System.unique_integer([:positive])}"
    ws = thread.workspace_id

    case Server.Workspaces.seat(ws, %{name: name, archetype: kind}) do
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
          post_brief(restaffed, "→ #{name} leads (#{thread.stage} stage)#{note}")
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
    with %{index: index} <- ws |> Server.Tmux.list_windows() |> Server.Tmux.leaf_tab(thread.id),
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

  # merged: the thread's work is done (closing it marks its ticket done), and what changed rolls out
  defp finish(thread, %{repo: repo, from: from, to: to}) do
    {:ok, _} = Server.Channel.close_thread(thread)
    Server.Rollout.after_merge(%{repo: repo, from: from, to: to, thread_id: thread.id})
    landed = "⤵ landed as #{String.slice(to, 0, 7)}"

    case Server.Workline.Publish.publish(repo, thread.slug, thread.title) do
      {:ok, url} -> post_brief(thread, "#{landed}; published as #{url} (GitHub merges it once its checks pass)")
      :none -> post_brief(thread, landed)
      {:error, why} -> post_brief(thread, "#{landed}, but not published to GitHub: #{why}")
    end
  rescue
    e ->
      why = "merged, but its close-out failed (not published to GitHub): #{Exception.message(e)}"
      require(Logger) && Logger.warning("workline #{thread.slug}: #{why}")
      post_brief(thread, "⚠ #{why}")
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
    `TLON_SMOKE_HOLD=1 mise run release:smoke -- work/#{thread.slug}` builds it on its own port and db (it prints the url), \
    smokes it and keeps it up; drive it with `TLON_URL=<the url it printed> mise run office:drive -- <keys>`. \
    Never :4040, the live service. Then submit_qa: pass, or fail with the finding — what you pressed and \
    the screen text you saw.\
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
end
