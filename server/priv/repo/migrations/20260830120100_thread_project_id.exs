defmodule Server.Repo.Migrations.ThreadProjectId do
  use Ecto.Migration

  # Additive (Workspace ▸ Project ▸ Thread, 2026-08-30): threads gain an optional
  # `project_id`. No data backfill here — existing threads keep routing by `workspace_id`
  # (unchanged); assigning them to a default project per workspace is a later, careful
  # step. SQLite allows a REFERENCES clause on a freshly-added column.
  def change do
    execute(
      "ALTER TABLE thread ADD COLUMN project_id INTEGER REFERENCES project(id)",
      "ALTER TABLE thread DROP COLUMN project_id"
    )
  end
end
