defmodule Server.Repo.Migrations.TicketKind do
  use Ecto.Migration

  # an epic is a ticket that holds other tickets (epics design §2); the closed set is CHECK'd like status/priority
  def change do
    execute(
      "ALTER TABLE ticket ADD COLUMN kind TEXT NOT NULL DEFAULT 'ticket' CONSTRAINT ticket_kind_check CHECK (kind IN ('ticket','epic'))",
      "ALTER TABLE ticket DROP COLUMN kind"
    )
  end
end
