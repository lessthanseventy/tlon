defmodule Server.WorkspaceAgent do
  @moduledoc """
  A seat on a workspace's bench, as a row: which `agent` this workspace employs, and in what
  `archetype`. The table behind `Server.Coworker`; `Server.Workspaces.bench/1` is the read.

  `archetype` is on the join, not the agent, because the same coworker can be a builder in one
  workspace and a reviewer in the next. `sort` ascends — a new seat appends at the bottom.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "workspace_agent" do
    field :workspace_id, :integer
    field :agent_id, :integer
    field :archetype, :string
    field :sort, :integer, default: 0
    field :created_at, :utc_datetime
  end

  @mutable [:archetype, :sort]

  @doc """
  Seat an agent on a workspace's bench. The DB's UNIQUE(workspace_id, agent_id) is the one guard
  against seating the same coworker twice — `unique_constraint` only translates its rejection.
  """
  def seat_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:workspace_id, :agent_id | @mutable])
    |> validate_required([:workspace_id, :agent_id])
    |> unique_constraint([:workspace_id, :agent_id])
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Edit a seat's archetype or order. Which workspace and which agent are its identity, not fields."
  def edit_changeset(%__MODULE__{} = seat, attrs), do: cast(seat, attrs, @mutable)
end
