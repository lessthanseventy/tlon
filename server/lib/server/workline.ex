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
         :ok <- verified_artifact(thread, checker) do
      if gated?(thread), do: park(thread, checker), else: flip(thread)
    else
      {:error, {:artifact_missing, why}} when thread.stage == "verify" ->
        if Keyword.get(opts, :reverify, checker == Git),
          do: reverify(thread, why),
          else: {:error, {:artifact_missing, why}}

      other ->
        other
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
  """
  def approve(thread, opts \\ [])

  def approve(%Thread{awaiting: awaiting} = thread, opts) when not is_nil(awaiting),
    do: landing(thread.id, fn -> do_approve(thread, opts) end)

  def approve(%Thread{}, _opts), do: {:error, :nothing_awaiting}

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

    with :ok <- verified_artifact(thread, checker) do
      if queue?(thread, checker, opts), do: queue(thread), else: approve_now(thread, checker, opts)
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

  defp queue(thread) do
    with {:ok, queued} <- thread |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update(),
         {:ok, _job} <- Server.Jobs.enqueue(Server.Jobs.Land.new(%{thread_id: thread.id})) do
      post_brief(
        queued,
        "⧗ approved — in the merge queue: it lands once rebased onto main and green there, one landing at a time"
      )

      {:ok, queued}
    else
      {:error, why} ->
        {:ok, _} = thread |> Thread.workline_stage_changeset(%{awaiting: thread.awaiting}) |> Repo.update()
        {:error, {:queue, why}}
    end
  end

  @doc """
  The merge queue's turn for `thread` (`Server.Jobs.Land`): land `work/<slug>` rebased onto main,
  gated there before main moves. Green: merged, closed, published. A conflict or a red gate sends
  it back to build, its builder told why — the operator approved; the fix is the builder's. A thread
  no longer queued (re-parked, closed, moved on) is left alone. `opts[:merge]`/`opts[:gate]` swap the
  merger and the gate (tests). `{:ok, thread}` | `{:error, {:bounced, why}}`.
  """
  def land_queued(thread, opts \\ [])

  def land_queued(%Thread{stage: "review", awaiting: nil, state: "open"} = thread, opts) do
    merger = Keyword.get(opts, :merge, Server.Workline.Merge)
    gate = Keyword.get_lazy(opts, :gate, fn -> &Server.Jobs.Land.gate(thread, &1, &2) end)
    repo = Git.root(thread)

    case merger.merge(repo, thread.slug, gate: gate) do
      {:ok, moved} ->
        {:ok, flipped} = flip(thread)
        finish(flipped, Map.put(moved, :repo, repo))
        {:ok, flipped}

      {:error, why} ->
        bounce(thread, why)
    end
  end

  def land_queued(thread, _opts), do: {:ok, thread}

  # back to build: the stage and its ledger row in one write, the builder restaffed and told why
  defp bounce(thread, why) do
    {:ok, back} =
      Repo.transaction(fn ->
        {:ok, back} = thread |> Thread.workline_stage_changeset(%{stage: "build", awaiting: nil}) |> Repo.update()

        {:ok, _event} =
          Dossier.record_event(%{
            thread_id: thread.id,
            kind: "stage_advanced",
            correlation: "workline:#{thread.slug}",
            detail: %{"from" => "review", "to" => "build", "bounced" => why}
          })

        back
      end)

    back = restaff(back)
    Server.Bus.broadcast({:workline_advanced, back})

    post_brief(
      back,
      "↩ back to build — the merge queue couldn't land it: #{why} Rebase work/#{thread.slug} onto main, " <>
        "fix it test-first, then advance_stage; it comes back through verify and review."
    )

    Server.Sheriff.report(back, "the merge queue bounced it back to build: #{why}")
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
  Whether a workline stands at its gate — a gated stage whose owed artifact is there, which is when
  `advance` parks it — so an `awaiting` on it is that gate, which only an approval clears. Anywhere
  else (an ungated stage, or a gated one whose artifact isn't written yet) it is a worker's question,
  which a reply clears. A machine-born intent parks before its artifact by design: always a gate.
  `opts[:artifacts]` swaps the checker (tests).
  """
  def at_gate?(thread, opts \\ [])
  def at_gate?(%Thread{stage: "intent", born: "machine"}, _opts), do: true

  def at_gate?(%Thread{stage: stage} = thread, opts) do
    stage in @gated and match?({:ok, _}, Keyword.get(opts, :artifacts, Git).check(thread, Map.fetch!(@owed, stage)))
  rescue
    # an artifact that can't even be checked (no slug, no repo): the cautious reading, a gate
    _ -> true
  end

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

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

    case verified_artifact(thread, checker) do
      :ok -> {:ok, "#{thread.stage} artifact committed"}
      {:error, {:artifact_missing, why}} -> {:error, why}
    end
  end

  # Each stage is led by its kind of worker from the workspace's bench, so a workline hands itself
  # on as it moves; intent by the bench's lead (the manager), who takes the ask in. Best-effort (the
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
  # else the first of the kind not leading another live workline (one only waiting on the operator
  # does not count — its session waits in its own window); else, the kind being on the bench but
  # all busy, one more is hired. A kind the bench lacks is never invented.
  defp restaff(thread, kind) do
    of_kind = thread.workspace_id |> Server.Workspaces.bench() |> Enum.filter(&(&1.archetype == kind))
    current = Server.Channel.thread_lead(thread.id)

    cond do
      of_kind == [] -> restaff_miss(thread, kind, "no #{kind} on the workspace's bench")
      Enum.any?(of_kind, &(&1.name == current)) -> thread
      free = Enum.find(of_kind, &(not leading_another?(&1, thread))) -> hand_to(thread, kind, free.name)
      true -> hire_for(thread, kind, of_kind)
    end
  rescue
    e -> restaff_miss(thread, kind, Exception.message(e))
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
    post_brief(thread, "⤵ merged into main as #{String.slice(to, 0, 7)}")
    {:ok, _} = Server.Channel.close_thread(thread)
    Server.Rollout.after_merge(%{repo: repo, from: from, to: to, thread_id: thread.id})

    case Server.Workline.Publish.publish(repo, thread.slug, thread.title) do
      {:ok, url} -> post_brief(thread, "⇪ published as #{url} (GitHub merges it once its checks pass)")
      :none -> :ok
      {:error, why} -> post_brief(thread, "⚠ landed here but not on GitHub: #{why}")
    end
  rescue
    e ->
      require(Logger) &&
        Logger.warning("workline #{thread.slug}: merged, but its close-out failed: #{Exception.message(e)}")
  end
end
