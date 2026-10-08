defmodule Server.Quest do
  @moduledoc """
  A one-off thing the operator does (life step 4, spec §2): "book the dentist". `due_at` is
  optional. `done_at` is set once, by `Server.Life.quest_done/2`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "quest" do
    field :title, :string
    field :due_at, :utc_datetime
    field :xp, :integer, default: 10
    field :done_at, :utc_datetime
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
  end

  @mutable [:title, :due_at, :xp]

  def create_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :title])
    |> validate_number(:xp, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  def done_changeset(%__MODULE__{} = q, at) do
    change(q, done_at: DateTime.truncate(at, :second), updated_at: DateTime.truncate(DateTime.utc_now(), :second))
  end
end
