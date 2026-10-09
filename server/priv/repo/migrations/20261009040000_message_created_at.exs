defmodule Server.Repo.Migrations.MessageCreatedAt do
  use Ecto.Migration

  # the time-windowed reads (recent notices for the desktop's toasts, the unheard-wake sweep, the
  # in-tray) were sequential scans of the whole message table on every poll
  def change do
    create index(:message, [:created_at])
  end
end
