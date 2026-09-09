defmodule Server.ChannelRow do
  @moduledoc """
  A channel row (UX slice 1b): `#<name>` inside a workspace — `general` (one per workspace, the
  crew's home when there is no specific work) or `topic`. Named `ChannelRow` because
  `Server.Channel` is the conversational context (threads, messages) and predates this table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "channel" do
    field :workspace_id, :integer
    field :name, :string
    field :kind, :string, default: "topic"
    field :created_at, :utc_datetime
  end

  @name ~r/\A[a-z0-9][a-z0-9_-]{0,39}\z/

  @doc "A new channel: lowercase slug-ish name, unique per workspace (DB)."
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:workspace_id, :name, :kind])
    |> validate_required([:workspace_id, :name, :kind])
    |> validate_format(:name, @name)
    |> validate_inclusion(:kind, ["general", "topic"])
    |> put_change(:created_at, DateTime.utc_now(:second))
    |> unique_constraint([:workspace_id, :name])
  end
end
