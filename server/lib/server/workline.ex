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

  This module opens, promotes and flags a workline and is the one door callers use: the rest lives
  in `Server.Workline.Stage` (the machine, its gates and approval), `Review` (verdicts, self-review,
  QA, the grade's reach), `Landing` (the merge queue's turn, requeue, reland, publish), `SendBack`,
  `Staffing` (who leads a stage) and `Shared`.
  """

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Brief
  alias Server.Workline.Landing
  alias Server.Workline.Review
  alias Server.Workline.SendBack
  alias Server.Workline.Shared
  alias Server.Workline.Staffing
  alias Server.Workline.Stage

  @stages Stage.stages()

  defdelegate stages, to: Stage
  defdelegate restaff_now(thread), to: Staffing
  defdelegate staff_kind(stage), to: Staffing
  defdelegate escalate(thread, why), to: Staffing
  defdelegate suggest_lead(workspace_id, kind, text, grade), to: Staffing

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
        thread = Staffing.staff_opened(thread, wanted)
        Shared.post_brief(thread, Brief.stage_message(thread))
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

        Shared.post_brief(tracked, Brief.stage_message(tracked))
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

  defdelegate advance(thread, opts \\ []), to: Stage

  defdelegate approve(thread, opts \\ []), to: Stage

  defdelegate landing(thread_id, fun), to: Landing

  defdelegate approval(thread), to: Stage

  defdelegate branch_head(thread), to: Stage

  defdelegate reopen(thread), to: Landing

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

  defdelegate gate_summary(thread), to: Stage

  defdelegate review_verdict(thread, verdict, author, opts \\ []), to: Review

  defdelegate self_review(thread, author), to: Review

  defdelegate qa_verdict(thread, verdict, author, report, opts \\ []), to: Review

  defdelegate graded(thread, opts \\ []), to: Review

  defdelegate grade_limits(thread), to: Review

  defdelegate limit_hit?(thread), to: Review

  defdelegate red_verify(thread, finding), to: Stage

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
      Shared.post_brief(thread, evidence)
      {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: Shared.operator()}) |> Repo.update()
      Server.Bus.broadcast({:workline_gated, parked})
      Shared.post_brief(parked, Brief.gate_message(parked))
      {:ok, parked}
    end
  end

  defdelegate at_gate?(thread, opts \\ []), to: Stage

  defdelegate proof(thread, opts \\ []), to: Stage

  defdelegate owed_status(thread, opts \\ []), to: Stage

  defdelegate qa_leads?(thread, opts \\ []), to: Stage

  defdelegate republish(thread, run \\ &Server.Cmd.run/3), to: Landing

  defdelegate published_by_hand(thread, url), to: Landing

  defdelegate publish_correlation(thread), to: Landing

  # A thread opens with the manager as its lead; a workline is a builder's — a free one, else one
  # hired beside the bench's busy builders (restaff). A bench with no builder to give it to leaves
  # it unled for triage: the manager never keeps it.
  defp unseat_manager(thread) do
    if manager_leads?(thread) do
      restaffed = Staffing.restaff(thread)

      if manager_leads?(restaffed) do
        Staffing.close_leaf(restaffed)
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
end
