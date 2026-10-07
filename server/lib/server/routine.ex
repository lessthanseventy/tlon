defmodule Server.Routine do
  @moduledoc """
  A recurring thing the operator does (life step 4, spec §2): "brush teeth", nightly. `every` is
  a cron expression or a shortcut (`@daily`, `@weekly` — `Server.Schedules`' own parser, no
  second one). `window_minutes` is how long after `every` fires it still counts on time.
  `tile`, if set, names a room tile (uninterpreted here — the Floor track's business).
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "routine" do
    field :title, :string
    field :every, :string
    field :window_minutes, :integer, default: 60
    field :xp, :integer, default: 10
    field :tile, :string
    field :enabled, :boolean, default: true
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
  end

  @mutable [:title, :every, :window_minutes, :xp, :tile, :enabled]

  def create_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :title, :every])
    |> validate_every()
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  def update_changeset(%__MODULE__{} = r, attrs) do
    r
    |> cast(attrs, @mutable)
    |> validate_required([:title, :every])
    |> validate_every()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_every(cs) do
    case get_field(cs, :every) do
      nil ->
        cs

      every ->
        if match?({:ok, _}, Oban.Cron.Expression.parse(every)),
          do: cs,
          else: add_error(cs, :every, "not a cron: #{every}")
    end
  end
end
