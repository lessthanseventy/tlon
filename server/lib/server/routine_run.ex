defmodule Server.RoutineRun do
  @moduledoc """
  One completion of a `Server.Routine` (life step 4, spec §2) — the ONLY row written when the
  operator does the thing. `due_at` is the occurrence it satisfies; `late` is computed once, at
  the stamp, and never recomputed. Immutable: no `updated_at`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "routine_run" do
    field :due_at, :utc_datetime
    field :done_at, :utc_datetime
    field :late, :boolean
    field :created_at, :utc_datetime
    belongs_to :routine, Server.Routine
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:routine_id, :due_at, :done_at, :late])
    |> validate_required([:routine_id, :due_at, :done_at, :late])
    |> foreign_key_constraint(:routine_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
