defmodule Server.Project do
  @moduledoc """
  A project (Workspace ▸ Project ▸ Thread, 2026-08-30): a named effort inside a workspace,
  spanning one or more repos. The middle tier of the container hierarchy — threads live
  under a project, a workspace holds many. `repos` is a JSON list of `%{name, path, url?}`
  (a project member, like `Server.Workspace`'s `paths`, not its own table — so the Ecto
  `Server.Repo` isn't shadowed); `knobs` is a free-form JSON map (per-project knobs, incl.
  its ticket backend later). `name` is unique WITHIN a workspace, guarded by the DB's
  `UNIQUE (workspace_id, name)`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "project" do
    field :name, :string
    field :repos, Server.JSONColumn
    field :knobs, Server.JSONColumn
    field :created_at, :utc_datetime
    belongs_to :workspace, Server.Workspace
  end

  @mutable [:name, :repos, :knobs]

  @doc """
  Register a project under `workspace_id`. `workspace_id` + `name` are required; `name` is
  unique within the workspace (DB). Stamps `created_at` (second-truncated UTC, like the
  workspace/fact schemas).
  """
  def register_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :name])
    # Translates the DB's UNIQUE(workspace_id, name) into an {:error, changeset} so a
    # duplicate register is graceful, not a crash.
    |> unique_constraint(:name, name: "project_workspace_id_name_index")
    |> foreign_key_constraint(:workspace_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Edit a project's mutable fields (`name`/`repos`/`knobs`). `workspace_id` + `created_at` are immutable."
  def edit_changeset(%__MODULE__{} = project, attrs) do
    project
    |> cast(attrs, @mutable)
    |> validate_required([:name])
    |> unique_constraint(:name, name: "project_workspace_id_name_index")
  end
end
