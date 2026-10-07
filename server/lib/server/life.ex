defmodule Server.Life do
  @moduledoc """
  XP, level and streaks as DERIVED VIEWS over `Server.RoutineRun`/`Server.Quest` (life step 4,
  spec §3) — nothing is cached. Every function scopes to one `workspace_id` except the pure
  integer math (`level/1`, `next_level_at/1`).
  """

  import Ecto.Query

  alias Server.Quest
  alias Server.Repo
  alias Server.Routine
  alias Server.RoutineRun
  alias Server.Schedules

  @doc "floor(sqrt(xp / 100)) — quick at first, slows down. A placeholder curve (spec §10)."
  @spec level(integer) :: integer
  def level(xp) when xp >= 0, do: xp |> Kernel./(100) |> :math.sqrt() |> Float.floor() |> trunc()

  @doc "The absolute xp threshold for `level(xp) + 1` — a stable target, not a remaining count."
  @spec next_level_at(integer) :: integer
  def next_level_at(xp) do
    next = level(xp) + 1
    100 * next * next
  end

  @doc "The most recent occurrence of `routine.every` at or before `now`, or nil if none has fired yet."
  @spec current_due_at(Routine.t(), DateTime.t()) :: DateTime.t() | nil
  def current_due_at(%Routine{every: every, created_at: created_at}, now) do
    walk_due(every, created_at, now, nil)
  end

  defp walk_due(every, cursor, now, last) do
    next = Schedules.next_occurrence(every, cursor)

    if DateTime.compare(next, now) == :gt do
      last
    else
      walk_due(every, next, now, next)
    end
  end

  @doc "The occurrence of `routine.every` strictly before `before_due_at`, or nil."
  @spec previous_due_at(Routine.t(), DateTime.t()) :: DateTime.t() | nil
  def previous_due_at(%Routine{} = routine, before_due_at) do
    current_due_at(routine, DateTime.add(before_due_at, -1, :second))
  end

  @doc "done_at strictly after due_at + window_minutes is late; at the boundary or before is on time."
  @spec late?(DateTime.t(), DateTime.t(), integer) :: boolean
  def late?(due_at, done_at, window_minutes) do
    DateTime.compare(done_at, DateTime.add(due_at, window_minutes * 60)) == :gt
  end

  @doc "Σ routine.xp over on-time runs + half (integer div) over late runs + Σ quest.xp over done quests."
  @spec xp(integer) :: integer
  def xp(workspace_id) do
    routine_xp =
      from(rr in RoutineRun,
        join: r in Routine,
        on: r.id == rr.routine_id,
        where: r.workspace_id == ^workspace_id,
        select: sum(fragment("CASE WHEN ? THEN ? / 2 ELSE ? END", rr.late, r.xp, r.xp))
      )
      |> Repo.one()

    quest_xp =
      from(q in Quest, where: q.workspace_id == ^workspace_id and not is_nil(q.done_at), select: sum(q.xp))
      |> Repo.one()

    (routine_xp || 0) + (quest_xp || 0)
  end

  @doc "Every enabled routine whose current due has no run yet, with how long is left in its window."
  @spec due(integer, DateTime.t()) :: [map()]
  def due(workspace_id, now \\ DateTime.utc_now()) do
    for routine <- Repo.all(from r in Routine, where: r.workspace_id == ^workspace_id and r.enabled),
        due_at = current_due_at(routine, now),
        due_at != nil,
        not has_run?(routine.id, due_at) do
      %{
        routine_id: routine.id,
        title: routine.title,
        due_at: due_at,
        window_remaining: DateTime.diff(DateTime.add(due_at, routine.window_minutes * 60), now)
      }
    end
  end

  @doc "Consecutive met dues counted back from now; 0 if the current due is unmet. Late still counts."
  @spec streak(Routine.t(), DateTime.t()) :: integer
  def streak(%Routine{} = routine, now \\ DateTime.utc_now()) do
    case current_due_at(routine, now) do
      nil -> 0
      due_at -> if has_run?(routine.id, due_at), do: 1 + streak_before(routine, due_at), else: 0
    end
  end

  defp streak_before(routine, due_at) do
    case previous_due_at(routine, due_at) do
      nil -> 0
      prev -> if has_run?(routine.id, prev), do: 1 + streak_before(routine, prev), else: 0
    end
  end

  defp has_run?(routine_id, due_at) do
    Repo.exists?(from rr in RoutineRun, where: rr.routine_id == ^routine_id and rr.due_at == ^due_at)
  end

  @doc """
  Stamps the routine's current due instance as done at `at` (default now). `{:ok, run, level_up}`,
  or `{:error, :not_found | :not_due | :already_done}`. `level_up` compares the workspace's level
  before and after this one write.
  """
  @spec routine_done(integer, DateTime.t()) :: {:ok, RoutineRun.t(), boolean} | {:error, atom}
  def routine_done(routine_id, at \\ DateTime.utc_now()) do
    at = DateTime.truncate(at, :second)

    case Repo.get(Routine, routine_id) do
      nil -> {:error, :not_found}
      routine -> stamp_routine(routine, at)
    end
  end

  defp stamp_routine(routine, at) do
    case current_due_at(routine, at) do
      nil -> {:error, :not_due}
      due_at -> if has_run?(routine.id, due_at), do: {:error, :already_done}, else: insert_run(routine, due_at, at)
    end
  end

  defp insert_run(routine, due_at, at) do
    xp_before = xp(routine.workspace_id)

    {:ok, run} =
      %{routine_id: routine.id, due_at: due_at, done_at: at, late: late?(due_at, at, routine.window_minutes)}
      |> RoutineRun.create_changeset()
      |> Repo.insert()

    {:ok, run, level(xp(routine.workspace_id)) > level(xp_before)}
  end

  @doc "Marks a quest done at `at` (default now). `{:ok, quest, level_up}` or `{:error, :not_found | :already_done}`."
  @spec quest_done(integer, DateTime.t()) :: {:ok, Quest.t(), boolean} | {:error, atom}
  def quest_done(quest_id, at \\ DateTime.utc_now()) do
    case Repo.get(Quest, quest_id) do
      nil -> {:error, :not_found}
      %Quest{done_at: done_at} when not is_nil(done_at) -> {:error, :already_done}
      quest -> do_quest_done(quest, at)
    end
  end

  defp do_quest_done(quest, at) do
    xp_before = xp(quest.workspace_id)
    {:ok, quest} = quest |> Quest.done_changeset(at) |> Repo.update()
    {:ok, quest, level(xp(quest.workspace_id)) > level(xp_before)}
  end

  @doc "A new routine. `{:ok, routine}` or `{:error, changeset}`."
  @spec create_routine(integer, map) :: {:ok, Routine.t()} | {:error, Ecto.Changeset.t()}
  def create_routine(workspace_id, attrs), do: Map.put(attrs, :workspace_id, workspace_id) |> Routine.create_changeset() |> Repo.insert()

  @doc "Edit a routine's mutable fields."
  @spec update_routine(Routine.t(), map) :: {:ok, Routine.t()} | {:error, Ecto.Changeset.t()}
  def update_routine(%Routine{} = routine, attrs), do: routine |> Routine.update_changeset(attrs) |> Repo.update()

  @doc "A new quest. `{:ok, quest}` or `{:error, changeset}`."
  @spec create_quest(integer, map) :: {:ok, Quest.t()} | {:error, Ecto.Changeset.t()}
  def create_quest(workspace_id, attrs), do: Map.put(attrs, :workspace_id, workspace_id) |> Quest.create_changeset() |> Repo.insert()

  @doc "The `GET /api/life` body for one workspace."
  @spec status(integer) :: map
  def status(workspace_id) do
    now = Schedules.local_now()
    routines = Repo.all(from r in Routine, where: r.workspace_id == ^workspace_id and r.enabled)
    xp = xp(workspace_id)

    %{
      xp: xp,
      level: level(xp),
      next_level_at: next_level_at(xp),
      streaks: Map.new(routines, &{&1.id, streak(&1, now)}),
      due: due(workspace_id, now),
      quests: open_quests(workspace_id),
      today: today(routines, now)
    }
  end

  defp open_quests(workspace_id) do
    Repo.all(
      from q in Quest,
        where: q.workspace_id == ^workspace_id and is_nil(q.done_at),
        order_by: [asc_nulls_last: q.due_at]
    )
  end

  defp today(routines, now) do
    today_date = DateTime.to_date(now)

    for routine <- routines,
        due_at = current_due_at(routine, now),
        due_at != nil,
        Date.compare(DateTime.to_date(due_at), today_date) == :eq do
      %{routine_id: routine.id, title: routine.title, due_at: due_at, done: has_run?(routine.id, due_at)}
    end
  end
end
