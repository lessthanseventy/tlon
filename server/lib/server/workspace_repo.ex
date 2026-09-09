defmodule Server.WorkspaceRepo do
  @moduledoc """
  One git-tracked entry of a workspace's scope (UX slice 5): a `path`, and — where the operator has
  said so — the `remote` it tracks and its `default_branch`. This is the table that replaced
  `workspace.paths`, a JSON list of bare strings the flake seeded by hand.

  `remote` and `default_branch` are NULLABLE and mean "not answered yet". The rows migrated from
  `paths` are scope globs (`modules/*`), not checkout roots, so inventing a remote for them would
  be a lie the operator has to find and undo later; the CONFIG pane is where they get answered.

  `sort` ascends — a new repo appends at the bottom, the way `paths ++ [entry]` did.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "workspace_repo" do
    field :workspace_id, :integer
    field :path, :string
    field :remote, :string
    field :default_branch, :string
    field :sort, :integer, default: 0
    field :created_at, :utc_datetime
  end

  @mutable [:path, :remote, :default_branch, :sort]

  @doc """
  Add a repo to a workspace. `workspace_id` and `path` are required; the DB's
  UNIQUE(workspace_id, path) is the one guard against a duplicate — `unique_constraint` only
  translates its rejection into `{:error, changeset}`.
  """
  def add_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:workspace_id | @mutable])
    |> validate_required([:workspace_id, :path])
    |> unique_constraint([:workspace_id, :path])
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Edit a repo row. `workspace_id` is immutable — moving a repo between workspaces is a delete and an add."
  def edit_changeset(%__MODULE__{} = repo, attrs) do
    repo
    |> cast(attrs, @mutable)
    |> validate_required([:path])
    |> unique_constraint([:workspace_id, :path])
  end
end
