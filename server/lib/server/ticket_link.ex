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

  A `parent` link runs `initiative → epic → ticket`, one level at a time: an epic's children are tickets, an
  initiative's are epics, and an initiative has no parent. The changeset refuses any other pairing and a
  second parent.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Server.Repo
  alias Server.Ticket

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
    |> validate_parent_law()
    |> unique_constraint([:from_id, :to_id, :kind], name: :ticket_link_from_id_to_id_kind_index)
    |> unique_constraint(:to_id, name: :ticket_link_one_parent, message: "already has a parent")
    |> foreign_key_constraint(:from_id)
    |> foreign_key_constraint(:to_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_not_self(changeset) do
    if get_field(changeset, :from_id) == get_field(changeset, :to_id),
      do: add_error(changeset, :to_id, "a ticket cannot link to itself"),
      else: changeset
  end

  # The parent law needs the two tickets, so it looks them up here; a missing ticket is left to the FK constraint.
  defp validate_parent_law(changeset) do
    with "parent" <- get_field(changeset, :kind),
         from_id when is_integer(from_id) <- get_field(changeset, :from_id),
         to_id when is_integer(to_id) <- get_field(changeset, :to_id),
         %Ticket{} = parent <- Repo.get(Ticket, from_id),
         %Ticket{} = child <- Repo.get(Ticket, to_id) do
      changeset
      |> pairing(parent.kind, child.kind)
      |> one_parent(from_id, to_id)
    else
      _ -> changeset
    end
  end

  defp pairing(changeset, "epic", "ticket"), do: changeset
  defp pairing(changeset, "initiative", "epic"), do: changeset

  defp pairing(changeset, "ticket", _),
    do: add_error(changeset, :from_id, "only an epic or an initiative can be a parent")

  defp pairing(changeset, _, "initiative"), do: add_error(changeset, :to_id, "an initiative cannot have a parent")
  defp pairing(changeset, _, "epic"), do: add_error(changeset, :to_id, "an epic's parent can only be an initiative")
  defp pairing(changeset, "initiative", _), do: add_error(changeset, :to_id, "an initiative holds epics, not tickets")

  defp one_parent(changeset, from_id, to_id) do
    other_parent? =
      Repo.exists?(from l in __MODULE__, where: l.kind == "parent" and l.to_id == ^to_id and l.from_id != ^from_id)

    if other_parent?, do: add_error(changeset, :to_id, "already has a parent"), else: changeset
  end
end
