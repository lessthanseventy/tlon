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

  @doc """
  Open a workline: a machine-scoped thread at stage "intent" + the `work/<slug>/` name.
  `{:ok, thread}` or `{:error, changeset}` (a taken slug is a UNIQUE refusal).
  """
  def open(attrs) do
    attrs = Map.put_new_lazy(attrs, :workspace_id, &Server.Bootstrap.default_workspace_id/0)

    with {:ok, thread} <-
           attrs |> Thread.workline_changeset() |> Repo.insert() |> Server.Bus.announce(:thread_opened) do
      # The brief IS the wake from stage one — the intent playbook must not wait for an advance.
      post_brief(thread, Brief.stage_message(thread))
      {:ok, thread}
    end
  end

  @doc """
  Promote a plain chat thread INTO the stage machine at `"build"` — tracking is the lazy
  path (reshape slice B): when real work lands on an untracked thread (both harnesses call
  this on the first successful `git commit`), the ticket condenses out of the work instead
  of competing with it. Slug derives from the title; a collision or unslugifiable title
  falls back to an id-suffixed name. Idempotent: an already-tracked thread is `{:ok, thread}`
  untouched. The ROOT machine thread is refused — the standing home is not a work item.
  """
  def promote(%Thread{stage: stage} = thread) when not is_nil(stage), do: {:ok, thread}

  def promote(%Thread{} = thread) do
    if Server.Channel.root_machine_thread?(thread) do
      {:error, :root_machine_thread}
    else
      do_promote(thread, promote_slug(thread))
    end
  end

  # Mirror flip/1: the stage landing and its ledger row commit together or not at all.
  # Re-reads INSIDE the transaction — two near-simultaneous callers (a cc hook and a pi
  # turn_end on one thread) must not double-promote and skew the ledger with twin events.
  # A changeset refusal (slug collision under the fallback's own TOCTOU) rolls back to a
  # tuple, never a raise — the MCP tool surfaces it.
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
    case fresh |> Thread.promote_changeset("build", slug) |> Repo.update() do
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
    base =
      thread.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 40)
      |> String.trim("-")

    cond do
      base == "" -> "thread-#{thread.id}"
      slug_taken?(base) -> "#{base}-#{thread.id}"
      true -> base
    end
  end

  defp slug_taken?(slug), do: Repo.get_by(Thread, slug: slug) != nil

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
      if gated?(thread), do: park(thread), else: flip(thread)
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

    # A machine-born intent's approval IS its acceptance: funes materializes intent.md from
    # the breach evidence so the chain stays intact and approve stays one verb. Only against
    # the REAL checker — a test stub must never make funes commit into the live repo.
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

  defp gated?(%Thread{stage: "intent", born: "machine"}), do: true
  defp gated?(%Thread{stage: stage}), do: stage in @gated

  defp park(thread) do
    {:ok, parked} = thread |> Thread.workline_stage_changeset(%{awaiting: "andrew"}) |> Repo.update()
    Server.Bus.broadcast({:workline_gated, parked})
    post_brief(parked, Brief.gate_message(parked))
    {:awaiting, parked}
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
    # builder still leading a review stage.
    flipped = if flipped.stage == "review", do: restaff_reviewer(flipped), else: flipped
    Server.Bus.broadcast({:workline_advanced, flipped})
    post_brief(flipped, Brief.stage_message(flipped))
    {:ok, flipped}
  end

  # Entering review: the workspace's reviewer takes the lead — the builder never approves its own
  # work by proxy. Best-effort (the stage already flipped and broadcast; a restaff fault must
  # not fail the advance) — but a MISS is posted, never silent: the operator sees that the
  # builder still holds a review it shouldn't.
  defp restaff_reviewer(%Thread{workspace_id: nil} = thread), do: restaff_miss(thread, "no workspace bound")

  defp restaff_reviewer(thread) do
    with %{roster: roster} when is_list(roster) <- Repo.get(Server.Workspace, thread.workspace_id),
         %{"name" => name} <- Enum.find(roster, &(&1["archetype"] == "reviewer" || &1[:archetype] == "reviewer")),
         {:ok, restaffed} <- Server.Channel.assign_lead(thread.id, "#{name}-machine") do
      post_brief(restaffed, "→ #{name}-machine leads (review stage)")
      restaffed
    else
      {:error, reason} -> restaff_miss(thread, inspect(reason))
      _ -> restaff_miss(thread, "no reviewer in the workspace's roster")
    end
  rescue
    e -> restaff_miss(thread, Exception.message(e))
  end

  defp restaff_miss(thread, why) do
    post_brief(thread, "⚠ review stage could not restaff a reviewer (#{why}) — the current lead still holds it")
    thread
  end

  # The brief IS the wake: a funes-authored message rides the lead-wake path (slice 2).
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
end
