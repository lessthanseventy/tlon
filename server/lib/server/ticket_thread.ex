defmodule Server.TicketThread do
  @moduledoc """
  A tie between a ticket and a thread (UX slice 4): `promoted | relates`.

  The many-to-many the single `promoted_thread_id` column could not express — a ticket may be
  discussed in several threads, a thread may carry several tickets, and either lives perfectly
  well alone. Promotion is one KIND of tie, not a different mechanism: `Server.Tickets.promote/2`
  writes a `promoted` row here and moves the ticket to `doing`, so there is one place a tie is
  recorded rather than a column and a table that can disagree.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(promoted relates)

  schema "ticket_thread" do
    field :kind, :string, default: "relates"
    field :created_at, :utc_datetime
    belongs_to :ticket, Server.Ticket
    belongs_to :thread, Server.Thread
  end

  @doc "The kinds a tie may have — the closed set the DB also CHECKs."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "Tie `ticket_id` to `thread_id`."
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:ticket_id, :thread_id, :kind])
    |> validate_required([:ticket_id, :thread_id])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint([:ticket_id, :thread_id, :kind], name: :ticket_thread_ticket_id_thread_id_kind_index)
    |> foreign_key_constraint(:ticket_id)
    |> foreign_key_constraint(:thread_id)
    |> put_change(:created_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
end
