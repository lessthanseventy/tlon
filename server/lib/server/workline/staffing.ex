defmodule Server.Workline.Staffing do
  @moduledoc """
  Who leads a workline at its stage: staffing the stage from the bench, handing a junior's workline
  up a grade, and the server's pick of a lead for an ask.
  """

  import Ecto.Query

  alias Server.Repo
  alias Server.Thread
  alias Server.Workline.Shared

  require Logger

  @hire_names ~w(averroes beatriz emma ireneo tzinacan ulrikke runeberg nolan pierre zunz)

  # Who leads each stage, by bench archetype: the stage's kind of work picks its worker. intent and
  # merged keep whoever has the thread.
  @staff_by_stage %{
    "spec" => "planner",
    "plan" => "planner",
    "build" => "builder",
    "verify" => "builder",
    "review" => "reviewer"
  }

  @doc """
  Staff `thread`'s current stage again from the bench as it is now — after a shift change, so a
  workline led by someone gone off shift is picked up by the crew on, the way any stage is staffed.
  `{:ok, thread}`.
  """
  def restaff_now(%Thread{} = thread), do: {:ok, restaff(thread)}

  @doc "The bench archetype that leads a workline at `stage` (planner, builder, reviewer), or nil."
  def staff_kind(stage), do: @staff_by_stage[stage]

  # Each stage is led by its kind of worker from the workspace's bench, so a workline hands itself
  # on as it moves; intent by the bench's lead (its first builder), who takes the ask in. Best-effort (the
  # stage already flipped; a restaff fault must not fail the advance). A workspace without that kind
  # keeps the current lead — quietly, except at review: a builder holding its own review is posted.
  @doc false
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

  @doc false
  def leading_another?(%Server.Coworker{agent_id: agent_id}, thread) do
    Repo.exists?(
      from t in Thread,
        where:
          t.agent_id == ^agent_id and t.id != ^thread.id and t.state == "open" and not is_nil(t.stage) and
            t.stage != "landed" and is_nil(t.awaiting)
    )
  end

  # Already theirs: nothing to hand over, and nothing to announce.
  @doc false
  def hand_to(thread, kind, name, note \\ nil) do
    if Server.Channel.thread_lead(thread.id) == name do
      thread
    else
      case Server.Channel.assign_lead(thread.id, name) do
        {:ok, restaffed} ->
          close_leaf(restaffed)
          model = model_label(thread.workspace_id, name)
          Shared.post_brief(restaffed, "#{Server.Trust.leads_line(name, thread.stage, model)}#{note}")
          restaffed

        {:error, reason} ->
          restaff_miss(thread, kind, inspect(reason))
      end
    end
  end

  # A thread has one window, its lead's: the old lead's must close or the new lead can never be
  # spawned (the builder kept the leaf and did verify's job; the reviewer's brief went nowhere).
  # The brief that follows spawns the new lead, as `Server.Sweep.hand_off/2` does.
  @doc false
  def close_leaf(%Thread{workspace_id: ws} = thread) when not is_nil(ws) do
    with %{index: index} <- Server.Sweep.leaf_window(thread, "close_leaf"),
         do: Server.Tmux.kill_window(ws, index)
  end

  def close_leaf(_thread), do: :ok

  # A manager's named lead is the one pick when it fits (`unfit/2`); else the stage's own pick leads
  # and the thread says why — one seat either way.
  @doc false
  def staff_opened(thread, nil), do: restaff(thread)

  def staff_opened(thread, wanted) do
    seat =
      thread.workspace_id && thread.workspace_id |> Server.Workspaces.bench_all() |> Enum.find(&(&1.name == wanted))

    case seat && unfit(thread, seat) do
      why when is_binary(why) ->
        staffed = restaff(thread)

        case Server.Channel.thread_lead(staffed.id) do
          nil ->
            hand_to(staffed, @staff_by_stage[thread.stage] || "lead", wanted)

          lead ->
            Shared.post_brief(staffed, "→ #{lead} leads, not #{wanted}: #{why} (one coworker, one workline)")
            staffed
        end

      _ ->
        hand_to(thread, @staff_by_stage[thread.stage] || "lead", wanted)
    end
  end

  # trust only breaks ties, so a lookup that fails leaves the candidate neutral (no `trust` key)
  # instead of dropping the handoff
  @doc false
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

  defp restaff_miss(thread, "reviewer", why) do
    Shared.post_brief(
      thread,
      "⚠ review stage could not restaff a reviewer (#{why}) — the current lead still holds it"
    )

    thread
  end

  defp restaff_miss(thread, _kind, _why), do: thread

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

  # why `seat` cannot lead `thread`, or nil
  defp unfit(thread, seat) do
    kind = @staff_by_stage[thread.stage]

    cond do
      kind && seat.archetype != kind -> "#{seat.name} is a #{seat.archetype}; the #{thread.stage} stage is a #{kind}'s"
      leading_another?(seat, thread) -> "#{seat.name} is leading another workline"
      true -> nil
    end
  end
end
