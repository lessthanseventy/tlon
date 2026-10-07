defmodule Server.Life do
  @moduledoc """
  XP, level and streaks as DERIVED VIEWS over `Server.RoutineRun`/`Server.Quest` (life step 4,
  spec §3) — nothing is cached. Every function scopes to one `workspace_id` except the pure
  integer math (`level/1`, `next_level_at/1`).
  """

  alias Server.Routine
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
end
