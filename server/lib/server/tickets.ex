defmodule Server.Tickets do
  @moduledoc """
  The tickets context (2026-08-30): the lightweight terminal tracker's write pipe + reads over
  the `ticket` table (the `local` backend). Workspace-scoped. Agents and the operator both file
  here (MCP `file_ticket`), and a filed ticket **promotes** into a thread when work starts. Every
  write announces on `Server.Bus`'s tickets topic so the board refreshes.

  Backend note: `local` is the only backend today. When a workspace points at Jira/GitHub, an
  adapter (under `modules/adapters`) will implement the same file/list/update verbs behind a
  `TicketBackend` behaviour — introduced with that first adapter (YAGNI until a 2nd impl exists).
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Repo
  alias Server.Ticket

  @doc "File a ticket. `{:ok, ticket}` or `{:error, changeset}`."
  def file(attrs) do
    attrs |> Ticket.file_changeset() |> Repo.insert() |> Bus.announce(:ticket_filed)
  end

  @doc "Tickets in a workspace, newest-first — the board maps over these."
  def in_workspace(workspace_id) do
    Repo.all(from t in Ticket, where: t.workspace_id == ^workspace_id, order_by: [desc: t.id])
  end

  @doc "Open (not-done) tickets in a workspace — the capture net minus the archive."
  def open_in_workspace(workspace_id) do
    Repo.all(
      from t in Ticket,
        where: t.workspace_id == ^workspace_id and t.status != "done",
        order_by: [desc: t.id]
    )
  end

  @doc "A ticket by id, or nil."
  def get(id), do: Repo.get(Ticket, id)

  @doc "Update a ticket's mutable fields. `{:ok, ticket}` or `{:error, changeset}`."
  def update(%Ticket{} = ticket, attrs) do
    ticket |> Ticket.update_changeset(attrs) |> Repo.update() |> Bus.announce(:ticket_updated)
  end

  @doc "Promote a ticket into the thread it became (links it + moves it to `doing`)."
  def promote(%Ticket{} = ticket, thread_id) do
    ticket |> Ticket.promote_changeset(thread_id) |> Repo.update() |> Bus.announce(:ticket_updated)
  end

  @doc "Remove a ticket."
  def remove(%Ticket{} = ticket) do
    ticket |> Repo.delete() |> Bus.announce(:ticket_removed)
  end
end
