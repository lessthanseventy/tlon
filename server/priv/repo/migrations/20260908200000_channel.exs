defmodule Server.Repo.Migrations.Channel do
  use Ecto.Migration

  # Channels (UX slice 1b, 2026-09-08): the layer between a workspace and its threads. Every
  # workspace has one `general` channel (what the hidden "root machine thread" stood in for) and
  # any number of `topic` channels. `thread.channel_id` is nullable in the DB (SQLite can't add
  # a NOT NULL column with an FK to a table it is creating) — the app treats nil as "#general":
  # this migration backfills every existing thread into its workspace's #general, and
  # `Server.Channel.open_thread/1` defaults it.
  def up do
    execute("""
    CREATE TABLE channel (
      id INTEGER PRIMARY KEY,
      workspace_id INTEGER NOT NULL REFERENCES workspace(id),
      name TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'topic' CHECK (kind IN ('general','topic')),
      created_at TEXT NOT NULL,
      UNIQUE (workspace_id, name)
    )
    """)

    execute("ALTER TABLE thread ADD COLUMN channel_id INTEGER REFERENCES channel(id)")

    # a #general per existing workspace, then every thread of that workspace into it
    execute("""
    INSERT INTO channel (workspace_id, name, kind, created_at)
    SELECT id, 'general', 'general', strftime('%Y-%m-%dT%H:%M:%SZ', 'now') FROM workspace
    """)

    execute("""
    UPDATE thread SET channel_id = (
      SELECT c.id FROM channel c WHERE c.workspace_id = thread.workspace_id AND c.kind = 'general'
    ) WHERE channel_id IS NULL
    """)
  end

  def down do
    execute("ALTER TABLE thread DROP COLUMN channel_id")
    execute("DROP TABLE channel")
  end
end
