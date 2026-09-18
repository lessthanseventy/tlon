defmodule Server.Repo.Migrations.WorldToWorkspace do
  use Ecto.Migration

  # Clarity rename (design slice E): the `world` composition IS a workspace. Rename the table and
  # the `thread.world_id` FK column to match the domain. SQLite (>= 3.25, legacy_alter_table off —
  # ecto_sqlite3's default) rewrites the child FK reference (`thread` REFERENCES world → workspace)
  # as part of the table rename, so only the column itself needs a second ALTER. Reversible: the
  # down path renames back. Data is untouched — a pure schema rename.
  def change do
    rename(table(:world), to: table(:workspace))
    rename(table(:thread), :world_id, to: :workspace_id)
  end
end
