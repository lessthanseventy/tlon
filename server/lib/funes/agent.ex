defmodule Server.Agent do
  @moduledoc """
  The durable identity (aleph §3): a named role — Sandra, Robert — that outlives
  every workspace and session. Its profile lives inline: a `mandate`, an `engine`
  strength requirement (never a model name, §8), and the five orthogonal axes
  (`context`, `sight`, `hands`, `trust`, `sandbox`, §3). A session is the ephemeral
  instance of an agent; the agent persists.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "agent" do
    field :name, :string
    field :mandate, :string
    field :engine, :string
    field :context, :string
    field :sight, :string
    field :hands, :string
    field :trust, :string
    field :sandbox, :string
    field :created_at, :utc_datetime
    has_many :sessions, Server.Session
  end

  @axes [:context, :sight, :hands, :trust, :sandbox]

  @doc """
  Register a new agent. A name, a mandate, and an engine strength requirement are
  required; the five axes are optional (thin is the safe default, §3). `name`'s
  uniqueness is enforced by the DB's UNIQUE index — `unique_constraint` only
  translates that rejection into `{:error, changeset}`, it does not re-check it
  (the DB stays the single guard, §10). A duplicate name is a plausible caller
  mistake worth a tidy error, unlike an orphan FK which is a bug that raises.
  """
  def register_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:name, :mandate, :engine | @axes])
    |> validate_required([:name, :mandate, :engine])
    |> unique_constraint(:name)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
