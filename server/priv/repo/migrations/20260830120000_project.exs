defmodule Server.Repo.Migrations.Project do
  use Ecto.Migration

  # A project (Workspace ▸ Project ▸ Thread, 2026-08-30): a named effort inside a
  # workspace, spanning one or more repos. Threads live under a project; a workspace holds
  # many projects. `repos` is JSON TEXT (a list of {name,path,url?} — like `workspace.paths`,
  # kept a project member rather than its own table so `Server.Repo` (the Ecto repo) isn't
  # shadowed and there's no row/FK we don't yet need). `knobs` is a JSON object. Plain SQL
  # like `workspace` — the CREATE a human reads at 2am is the point.
  def change do
    execute(
      """
      CREATE TABLE project (
        id INTEGER PRIMARY KEY,
        workspace_id INTEGER NOT NULL REFERENCES workspace(id),
        name TEXT NOT NULL,
        repos TEXT NOT NULL DEFAULT '[]',
        knobs TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        UNIQUE (workspace_id, name)
      )
      """,
      "DROP TABLE project"
    )
  end
end
