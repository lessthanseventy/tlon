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
  instead of flipping; `approve/1` is the operator's completion verb. Every completed flip
  records a `stage_advanced` event: the slice-6 ledger reads metrics out of rows that
  already exist.
  """

  import Ecto.Query

  alias Server.Dossier
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Artifacts.Git
  alias Server.Workline.Brief
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
        # The brief IS the wake from the entry stage — the opening playbook must not wait for an advance.
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
  otherwise. `opts[:artifacts]` swaps the checker (tests stub it; default is git).
  """
  def advance(%Thread{} = thread, opts \\ []) do
    checker = Keyword.get(opts, :artifacts, Git)

    with :ok <- advanceable(thread),
         :ok <- verified_artifact(thread, checker) do
      if gated?(thread), do: park(thread, checker), else: flip(thread)
    end
  end

  @doc """
  Complete a parked gate — the operator's verb (tlon-cli `approve`). RE-VERIFIES the owed
  artifact before flipping: a flag-parked intent (or an artifact that vanished since the
  park) cannot ride approval past the invariant. `{:ok, thread}`,
  `{:error, {:artifact_missing, why}}` (still parked), or `{:error, :nothing_awaiting}`.
  """
  def approve(thread, opts \\ [])

  def approve(%Thread{awaiting: awaiting} = thread, opts) when not is_nil(awaiting) do
    checker = Keyword.get(opts, :artifacts, Git)

    # A machine-born intent's approval IS its acceptance: server materializes intent.md from
    # the breach evidence so the chain stays intact and approve stays one verb. Only against
    # the REAL checker — a test stub must never make server commit into the live repo.
    if thread.stage == "intent" and thread.born == "machine" and checker == Git do
      Scribe.materialize_intent(thread)
    end

    with :ok <- verified_artifact(thread, checker) do
      {:ok, cleared} = thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()
      flip(cleared)
    end
  end

  def approve(%Thread{}, _opts), do: {:error, :nothing_awaiting}

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

  defp advanceable(%Thread{stage: nil}), do: {:error, :not_a_workline}
  defp advanceable(%Thread{stage: "merged"}), do: {:error, :terminal}
  defp advanceable(%Thread{awaiting: awaiting}) when not is_nil(awaiting), do: {:error, :awaiting_operator}
  defp advanceable(%Thread{stage: stage}) when stage in @stages, do: :ok
  # A stage outside the ring (hand-edited row, drifted data) is a typed refusal, not a crash.
  defp advanceable(%Thread{stage: stage}), do: {:error, {:invalid_stage, stage}}

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
  Whether a workline's stage is one whose exit is a gate — so an `awaiting` on it is that gate,
  which only an approval clears (on any other stage it is a worker's question, which a reply clears).
  """
  def at_gate?(%Thread{stage: "intent", born: "machine"}), do: true
  def at_gate?(%Thread{stage: stage}), do: stage in @gated

  defp gated?(thread), do: at_gate?(thread)

  defp park(thread, checker) do
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
        {:ok, flipped} = thread |> Thread.workline_stage_changeset(%{stage: to}) |> Repo.update()

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

    case verified_artifact(thread, checker) do
      :ok -> {:ok, "#{thread.stage} artifact committed"}
      {:error, {:artifact_missing, why}} -> {:error, why}
    end
  end

  # Each stage is led by its kind of worker from the workspace's bench, so a workline hands itself
  # on as it moves. Best-effort (the stage already flipped; a restaff fault must not fail the
  # advance). A workspace without that kind keeps the current lead — quietly, except at review:
  # a builder holding its own review is posted, never silent.
  defp restaff(%Thread{stage: stage} = thread) do
    case @staff_by_stage[stage] do
      nil -> thread
      kind -> restaff(thread, kind)
    end
  end

  defp restaff(%Thread{workspace_id: nil} = thread, kind), do: restaff_miss(thread, kind, "no workspace bound")

  defp restaff(thread, kind) do
    thread.workspace_id
    |> Server.Workspaces.bench()
    |> Enum.find(&(&1.archetype == kind))
    |> case do
      %Server.Coworker{name: name} -> hand_to(thread, kind, name)
      _ -> restaff_miss(thread, kind, "no #{kind} on the workspace's bench")
    end
  rescue
    e -> restaff_miss(thread, kind, Exception.message(e))
  end

  # Already theirs: nothing to hand over, and nothing to announce.
  defp hand_to(thread, kind, name) do
    if Server.Channel.thread_lead(thread.id) == name do
      thread
    else
      case Server.Channel.assign_lead(thread.id, name) do
        {:ok, restaffed} ->
          close_leaf(restaffed)
          post_brief(restaffed, "→ #{name} leads (#{thread.stage} stage)")
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
end
