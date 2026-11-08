defmodule Server.Repo.Migrations.ObanV14 do
  use Ecto.Migration

  # oban 2.24 verifies version 14 at start; the baseline migrated to 12, so the service's Oban
  # refuses to start without it.
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 12)
end
