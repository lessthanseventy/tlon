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
  alias Server.Workline.Brief
  alias Server.Workline.Landing
  alias Server.Workline.Review
  alias Server.Workline.SendBack
  alias Server.Workline.Stage

  require Logger

  @stages Stage.stages()
  # Who leads each stage, by bench archetype: the stage's kind of work picks its worker. intent and
  # merged keep whoever has the thread.
  @staff_by_stage %{
    "spec" => "planner",
    "plan" => "planner",
    "build" => "builder",
    "verify" => "builder",
    "review" => "reviewer"
  }

  defdelegate stages, to: Stage

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

  defdelegate landing_check(url, exit, tail), to: Landing

  defdelegate record_landing(thread, kind, detail), to: Landing

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

  defdelegate red_verify(thread, finding), to: Stage

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

  defdelegate at_gate?(thread, opts \\ []), to: Stage

  defdelegate proof(thread, opts \\ []), to: Stage

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

  defdelegate owed_status(thread, opts \\ []), to: Stage

  @doc "The bench archetype that leads a workline at `stage` (planner, builder, reviewer), or nil."
  def staff_kind(stage), do: @staff_by_stage[stage]

  defdelegate qa_leads?(thread, opts \\ []), to: Stage

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

  defdelegate finish(thread, moved, run), to: Landing

  defdelegate republish(thread, run \\ &Server.Cmd.run/3), to: Landing

  defdelegate published_by_hand(thread, url), to: Landing

  defdelegate publish_correlation(thread), to: Landing

  defdelegate publish(thread, repo, landed, ref, run, gated \\ nil), to: Landing

  defdelegate unpublished(thread, why), to: Landing

  defdelegate record_publish(thread, exit, tail), to: Landing

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

  def operator, do: Server.OperatorConfig.operator()

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
