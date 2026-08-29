defmodule Server.Issue do
  @moduledoc """
  A finding that outlives the session that found it (spec §5): what was found, the
  evidence, what would settle it, who found it, and a `state` the DB CHECKs. Ticket-
  shaped and local — this machine's own defects, never product work. `summary` is
  the only required field; any participant may raise anything (§5b).
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "issue" do
    field :summary, :string
    field :evidence, :string
    field :resolution, :string
    field :found_by, :string
    field :state, :string, default: "open"
    field :created_at, :utc_datetime
    belongs_to :thread, Server.Thread
  end

  @doc """
  Raise an issue. `summary` is required; `state` is not caller-settable (it opens
  open). The closed `state` set is the DB's CHECK (§10), never mirrored here.
  """
  def raise_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:thread_id, :summary, :evidence, :resolution, :found_by])
    |> validate_required([:summary])
    |> put_change(:state, "open")
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  @doc "Move an issue to a new state. The closed set is enforced by the DB CHECK alone."
  def state_changeset(issue, state) do
    change(issue, state: state)
  end
end
