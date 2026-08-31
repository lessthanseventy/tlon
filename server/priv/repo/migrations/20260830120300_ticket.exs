defmodule Server.Repo.Migrations.Ticket do
  use Ecto.Migration

  # A ticket (2026-08-30): a first-class, workspace-scoped issue — the lightweight terminal
  # tracker (no epics/sprints/ceremony). Filed in 2 seconds; does NOT spin up a thread;
  # PROMOTES into one (`promoted_thread_id`) when work starts. `status`/`priority` are DB-CHECK'd
  # closed sets; `labels` is a JSON list. `backend` is `local` now — `external_key`/`external_url`
  # carry an adapter-backed ticket (Jira/GitHub) when a workspace points elsewhere (follow-on).
  def change do
    execute(
      """
      CREATE TABLE ticket (
        id INTEGER PRIMARY KEY,
        workspace_id INTEGER NOT NULL REFERENCES workspace(id),
        project_id INTEGER REFERENCES project(id),
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'backlog' CHECK (status IN ('backlog','todo','doing','done')),
        priority TEXT NOT NULL DEFAULT 'med' CHECK (priority IN ('low','med','high')),
        labels TEXT NOT NULL DEFAULT '[]',
        assignee TEXT,
        backend TEXT NOT NULL DEFAULT 'local',
        external_key TEXT,
        external_url TEXT,
        promoted_thread_id INTEGER REFERENCES thread(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      "DROP TABLE ticket"
    )
  end
end
