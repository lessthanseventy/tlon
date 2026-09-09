defmodule Server.Workspace do
  @moduledoc """
  A workspace (workspaces/orbis Slice 1): a first-class composition — a git-tracked scope, a
  roster of archetype instances, and free-form `knobs` — that console reads to drive its
  picker/survey/spawn. Compositions are DATA (this table), capabilities are nix (the archetype
  templates); disjoint, so the two never conflict.

  `type` (code|life|blank) and `scope` (project|machine) are closed sets the DB
  CHECKs guard (§10) — the schema does not mirror them, a bad value raises at insert.
  `roster`/`knobs` are JSON columns (`Server.JSONColumn`): a list of maps and a map.

  The git-tracked scope is NOT here: it is `Server.WorkspaceRepo` rows (UX slice 5), reached
  through `Server.Workspaces.repos/1`. `paths` was a JSON list of bare strings with nowhere to
  record a remote or a default branch.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "workspace" do
    field :name, :string
    field :type, :string
    field :scope, :string
    field :roster, Server.JSONColumn
    field :knobs, Server.JSONColumn
    field :created_at, :utc_datetime
  end

  @mutable [:type, :scope, :roster, :knobs]

  @doc """
  Register a workspace. `name` is required and unique (DB); `type`/`scope` are the DB's
  own closed-set guards (§10), so a bad value raises at insert rather than being
  re-checked here. Stamps `created_at`, matching the fact schema's second-truncated
  UTC.
  """
  def register_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name | @mutable])
    |> validate_required([:name])
    # Not an app-side re-check: this only translates the DB's UNIQUE(name) violation
    # into an {:error, changeset} so a duplicate register is graceful, not a crash.
    |> unique_constraint(:name)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc """
  Edit a workspace's mutable fields (`type`/`scope`/`roster`/`knobs`). `name` and
  `created_at` are immutable — a workspace's identity and birth are not re-cast here.
  """
  def edit_changeset(%__MODULE__{} = workspace, attrs) do
    cast(workspace, attrs, @mutable)
  end
end
