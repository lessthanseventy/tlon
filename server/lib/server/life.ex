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
end
