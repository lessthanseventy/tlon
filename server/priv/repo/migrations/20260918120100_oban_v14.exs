defmodule Server.Repo.Migrations.ObanV14 do
  use Ecto.Migration

  # oban 2.24 verifies version 14 at start; the baseline migrated to 12, so the service's Oban
  # refused to start until this landed (found by the E/2 tests, 2026-09-18).
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 12)
end
