defmodule Server.TicketLink do
  @moduledoc """
  A tie between two tickets (UX slice 4): `blocks | relates | duplicates | parent`.

  Stored ONE way and read both. "A is blocked by B" is not a row — it is `B blocks A` read from
  the other end (`Server.Tickets.blockers/1`), so the two directions can never disagree and a
  delete cannot leave half a relationship behind. `relates` and `duplicates` are symmetric in
  meaning but still stored once; the reads union both ends.

  The DB refuses a self-link and a duplicate `(from, to, kind)`; both are re-validated here
  because tickets arrive from MCP callers, where a bad value should come back as a changeset
  rather than a raised constraint.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(blocks relates duplicates parent)

  schema "ticket_link" do
    field :kind, :string, default: "relates"
    field :created_at, :utc_datetime
    belongs_to :from, Server.Ticket, foreign_key: :from_id
    belongs_to :to, Server.Ticket, foreign_key: :to_id
  end

  @doc "The kinds a link may have — the closed set the DB also CHECKs."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Link `from_id` to `to_id`. Refuses a self-link and any kind outside the closed set."
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:from_id, :to_id, :kind])
    |> validate_required([:from_id, :to_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_not_self()
    |> unique_constraint([:from_id, :to_id, :kind], name: :ticket_link_from_id_to_id_kind_index)
    |> foreign_key_constraint(:from_id)
    |> foreign_key_constraint(:to_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :from_id) == get_field(changeset, :to_id),
      do: add_error(changeset, :to_id, "a ticket cannot link to itself"),
      else: changeset
  end
end
