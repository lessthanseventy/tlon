defmodule Server.Event do
  @moduledoc """
  Append-only, what happened — for happenings with **no other home** (spec §4).
  The closed `kind` the DB CHECKs is the outcomes and
  judgements no other table records: `work_landed`, `command_approved`,
  `check_passed`, `handoff_opened`. A message and a session are NOT events — they
  are their own rows with their own timestamps, and the timeline derives them; an
  event copying them would be a second source (§2) and a dual write (§10).
  `correlation` is the explicit id of the lifecycle a row belongs to; `detail` is
  JSON for a human to read, never queried.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "event" do
    field :kind, :string
    field :correlation, :string
    field :detail, Server.JSONColumn
    field :created_at, :utc_datetime
    belongs_to :thread, Server.Thread
  end

  @doc """
  Record an event. `kind` is required and the closed set is the DB's own CHECK
  (§10) — a kind outside it raises, never re-checked here.
  """
  def record_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :kind, :correlation, :detail])
    |> validate_required([:kind])
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
