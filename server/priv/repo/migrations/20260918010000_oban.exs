defmodule Server.Repo.Migrations.Oban do
  use Ecto.Migration

  # Oban's own tables (one-brain piece E): the job queue is a Postgres table, so a queued job
  # survives a restart like every other row.
  def up, do: Oban.Migration.up(version: 12)
  def down, do: Oban.Migration.down(version: 1)
end
