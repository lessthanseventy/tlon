defmodule Server.Repo.Migrations.Note do
  use Ecto.Migration

  # A note (2026-08-30): funes-native freeform scratch, agent-readable/writable. Polymorphic
  # scope via (`scope`, `scope_id`) — `global` (scope_id NULL) / `workspace` / `project` /
  # `thread`. NOT a real FK (it points at different tables by scope), so no REFERENCES — the
  # scope set is a DB CHECK (§10). `body` is markdown TEXT; `author` who wrote it.
  def change do
    execute(
      """
      CREATE TABLE note (
        id INTEGER PRIMARY KEY,
        scope TEXT NOT NULL DEFAULT 'global' CHECK (scope IN ('global','workspace','project','thread')),
        scope_id INTEGER,
        body TEXT NOT NULL DEFAULT '',
        author TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      "DROP TABLE note"
    )
  end
end
