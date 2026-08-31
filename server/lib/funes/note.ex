defmodule Server.Note do
  @moduledoc """
  A note (2026-08-30): funes-native freeform scratch — agent-readable/writable, the reason
  it's a durable row rather than a text file. Polymorphic scope via `(scope, scope_id)`:
  `global` (scope_id nil) / `workspace` / `project` / `thread`. `scope` is a DB-CHECK'd
  closed set (not re-mirrored app-side). `body` is markdown; `author` who wrote it. Both
  `created_at` and `updated_at` are stamped (a note is edited in place).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @scopes ~w(global workspace project thread)

  schema "note" do
    field :scope, :string, default: "global"
    field :scope_id, :integer
    field :body, :string, default: ""
    field :author, :string
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
  end

  @doc """
  Write a note. `body` required. `scope` defaults to `global` and is validated against the
  closed set app-side too (a bad scope should fail as a changeset, not raise at the DB, since
  it arrives from MCP callers). A non-global scope requires a `scope_id`. Stamps both times.
  """
  def write_changeset(attrs) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    %__MODULE__{}
    |> cast(attrs, [:scope, :scope_id, :body, :author])
    |> validate_required([:body])
    |> validate_inclusion(:scope, @scopes)
    |> validate_scope_id()
    |> put_change(:created_at, now)
    |> put_change(:updated_at, now)
  end

  @doc "Edit a note's `body` (and re-stamp `updated_at`). Scope/author/created_at are immutable."
  def edit_changeset(%__MODULE__{} = note, attrs) do
    note
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  # A scoped note (workspace/project/thread) must name its target; a global one must not.
  defp validate_scope_id(changeset) do
    scope = get_field(changeset, :scope)
    scope_id = get_field(changeset, :scope_id)

    cond do
      scope == "global" and not is_nil(scope_id) -> add_error(changeset, :scope_id, "must be nil for a global note")
      scope != "global" and is_nil(scope_id) -> add_error(changeset, :scope_id, "required for a #{scope} note")
      true -> changeset
    end
  end
end
