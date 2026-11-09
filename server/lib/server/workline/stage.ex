defmodule Server.Workline.Stage do
  @moduledoc """
  The stage machine: the ring, what each stage owes, the gates that park on the operator, and the
  moves through them: `advance/2`, `approve/2` and the approval that stands, the proof a landing
  carries, and a red verify's way back to build.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Artifacts.Git
  alias Server.Workline.Brief
  alias Server.Workline.Grade
  alias Server.Workline.Scribe

  # Stages whose EXIT waits on the operator; a machine-born intent gates its exit too.
  @gated ~w(spec review)

  @owed %{
    "intent" => {:file, "intent.md"},
    "spec" => {:file, "spec.md"},
    "plan" => {:file, "plan.md"},
    "build" => :branch,
    "verify" => :checks,
    "review" => {:file, "review.md"}
  }

  @stages ~w(intent spec plan build verify review landed)

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
         :ok <- Workline.qa_cleared(thread, opts) do
      if gated?(thread), do: park(thread, checker, opts), else: Workline.flip(thread)
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
      Keyword.get(opts, :as) == "uqbar" and Workline.limit_hit?(thread) ->
        {:error, :limit_hit}

      reason != "" and Workline.qa_owed(thread, opts) ->
        Workline.landing(thread.id, fn ->
          skip_qa(thread, reason)
          do_approve(thread, opts)
        end)

      thread.awaiting ->
        Workline.landing(thread.id, fn -> do_approve(thread, opts) end)

      true ->
        {:error, :nothing_awaiting}
    end
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

  @doc "The commit `work/<slug>` is at in the thread's repo, or nil without one."
  def branch_head(thread) do
    case Server.Git.cmd(Git.root(thread), ["rev-parse", "--verify", "--quiet", "work/#{thread.slug}^{commit}"]) do
      {sha, 0} -> String.trim(sha)
      _ -> nil
    end
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

    risk = if grade = Workline.grade(thread), do: " · #{Grade.line(grade)}", else: ""
    "#{verdict} · #{size}#{risk} — approve to land it through the merge queue"
  end

  def gate_summary(%Thread{stage: stage, slug: slug}), do: "work/#{slug}/#{stage}.md is ready — approve to move on"

  @doc """
  A red verify goes back to build on the same branch, its builder told what broke: the build is
  kept and fixed with its original context, never redone. Only from verify — a workline already
  moved on is left where it is. `{:ok, thread}` | `{:error, {:not_at, stage}}`.
  """
  def red_verify(%Thread{} = thread, finding) do
    Workline.move_back(
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
      Workline.qa_cleared(thread, opts) == :ok
  rescue
    # an artifact that can't even be checked (no slug, no repo): the cautious reading, a gate
    _ -> true
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
         :ok <- Workline.qa_cleared(thread, opts) do
      {:ok, "#{thread.stage} artifact committed"}
    else
      {:error, {:artifact_missing, why}} -> {:error, why}
      {:error, why} when is_binary(why) -> {:error, why}
    end
  end

  @doc "Whether `thread` owes a QA pass at review and its qa seat is the one leading it. `opts` as `advance/2`'s."
  def qa_leads?(thread, opts \\ []) do
    case Workline.qa_owed(thread, opts) do
      {seat, _paths} -> Server.Channel.thread_lead(thread.id) == seat.name
      nil -> false
    end
  end

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
    Workline.post_brief(
      thread,
      "⚠ couldn't merge work/#{thread.slug}: #{why} The gate stays parked; approve again once it's fixed."
    )

    {:error, {:merge, why}}
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

    Workline.post_brief(thread, "⚠ QA skipped by the operator: #{reason}")
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

  # any review verdict, even one from before verdicts recorded a sha
  defp reviewed_before?(thread),
    do:
      Repo.exists?(
        from e in Server.Event, where: e.thread_id == ^thread.id and e.correlation == ^"workline:#{thread.slug}:review"
      )

  # review.md stays on the branch across rounds: back at review after a bounce, the file is the last
  # round's, so only a verdict since the workline re-entered review is this round's review
  defp this_round({:ok, _} = ok, %Thread{stage: "review"} = thread) do
    if is_nil(Workline.since_review(thread, "workline:#{thread.slug}:review")) and reviewed_before?(thread),
      do: {:error, "work/#{thread.slug}/review.md is the last round's — submit_review this round's verdict"},
      else: ok
  end

  defp this_round(result, _thread), do: result

  defp still_open(%Thread{state: "closed"}), do: {:error, :closed}
  defp still_open(_thread), do: :ok

  defp owed_artifact(thread, checker),
    do: thread |> checker.check(Map.fetch!(@owed, thread.stage)) |> this_round(thread)

  # a reviewer that approved in review.md and advanced (rather than `submit_review`) still owes
  # QA: hand it to the qa seat as the verdict would, instead of refusing into a dead end
  defp hand_to_qa(thread, opts) do
    line = Keyword.get_lazy(opts, :review_line, fn -> Git.doc_line(thread, "review.md") end) || ""

    # review.md stays on the branch across rounds: with no verdict yet this round, an approval in it
    # is the last round's and owes nothing
    with true <- line =~ ~r/approve/i and not (line =~ ~r/request.?changes/i),
         false <- is_nil(Workline.since_review(thread, "workline:#{thread.slug}:review")) and reviewed_before?(thread),
         {seat, paths} <- Workline.qa_owed(thread, opts),
         false <- Server.Channel.thread_lead(thread.id) == seat.name do
      {:ok, Workline.to_qa(thread, seat, paths)}
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

  defp do_approve(thread, opts) do
    checker = Keyword.get(opts, :artifacts, Git)

    # A machine-born intent's approval IS its acceptance: server materializes intent.md from
    # the breach evidence so the chain stays intact and approve stays one verb. Only against
    # the REAL checker — a test stub must never make server commit into the live repo.
    if thread.stage == "intent" and thread.born == "machine" and checker == Git do
      Scribe.materialize_intent(thread)
    end

    with :ok <- verified_artifact(thread, checker),
         :ok <- Workline.reviewed_current(thread),
         :ok <- Workline.qa_cleared(thread, opts) do
      if queue?(thread, checker, opts),
        do: Workline.queue(thread, "approved", Keyword.get(opts, :as) || thread.awaiting || Workline.operator()),
        else: approve_now(thread, checker, opts)
    end
  end

  defp approve_now(thread, checker, opts) do
    with {:ok, landed} <- land(thread, checker, opts),
         {:ok, cleared} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         {:ok, flipped} <- Workline.flip(cleared) do
      if landed, do: Workline.finish(flipped, landed, Keyword.get(opts, :run, &Server.Cmd.run/3))
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

  defp same_code?(thread, sha, head), do: Workline.compare_code(thread, sha, head) == :same

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

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

  # An approval stands across commits that only touched work/<slug>/ (`approval/1`): a reviewer
  # re-committing review.md and advancing again re-queues the code, it does not ask for it twice.
  defp park(%Thread{stage: "review"} = thread, checker, opts) do
    case approval(thread) do
      %{"by" => by, "sha" => sha} ->
        Workline.queue(thread, "#{by}'s approval at #{String.slice(sha, 0, 7)} still stands", by)

      nil ->
        if Workline.auto_land?(thread, checker, opts),
          do: Workline.queue(thread, Workline.auto_land_note(thread, opts), "auto_land_risk"),
          else: park_on_operator(thread, checker)
    end
  end

  defp park(thread, checker, _opts), do: park_on_operator(thread, checker)

  defp park_on_operator(thread, checker) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: Workline.operator()}) |> Repo.update()
    Server.Bus.broadcast({:workline_gated, parked})
    proof = if parked.stage == "review", do: proof(parked, artifacts: checker)
    Workline.post_brief(parked, Brief.gate_message(parked, proof))
    {:awaiting, parked}
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
end
