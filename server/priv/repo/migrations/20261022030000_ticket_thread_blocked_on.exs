defmodule Server.Repo.Migrations.TicketThreadBlockedOn do
  use Ecto.Migration

  # a seat blocked on an open ticket (Server.Blocked) is a third kind of tie
  def change do
    execute(
      "ALTER TABLE ticket_thread DROP CONSTRAINT ticket_thread_kind_check, ADD CONSTRAINT ticket_thread_kind_check CHECK (kind IN ('promoted','relates','blocked_on'))",
      "ALTER TABLE ticket_thread DROP CONSTRAINT ticket_thread_kind_check, ADD CONSTRAINT ticket_thread_kind_check CHECK (kind IN ('promoted','relates'))"
    )
  end
end
