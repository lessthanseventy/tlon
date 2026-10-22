defmodule Server.Repo.Migrations.TicketKindInitiative do
  use Ecto.Migration

  # an initiative holds epics as an epic holds tickets (Server.TicketLink's parent law)
  def change do
    execute(
      "ALTER TABLE ticket DROP CONSTRAINT ticket_kind_check, ADD CONSTRAINT ticket_kind_check CHECK (kind IN ('ticket','epic','initiative'))",
      "ALTER TABLE ticket DROP CONSTRAINT ticket_kind_check, ADD CONSTRAINT ticket_kind_check CHECK (kind IN ('ticket','epic'))"
    )
  end
end
