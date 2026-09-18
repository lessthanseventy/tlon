defmodule Server.Repo.Migrations.ThreadStageCheck do
  use Ecto.Migration

  # Mirror the workline closed sets at the DB layer (§4: a closed set is guarded by a CHECK,
  # never only by an Elixir validation that could drift). SQLite cannot ALTER a CHECK, so the
  # 12-step rebuild. Two SQLite-isms: foreign_keys OFF for the swap (thread IS referenced —
  # child FK clauses name "thread" and re-resolve), and the WHOLE rebuild pinned to ONE pooled
  # connection via repo().checkout — DROP on one connection + RENAME on another sees a stale
  # schema snapshot and refuses ("table thread already exists").
  @disable_ddl_transaction true
  @disable_migration_lock true

  @stages "'intent', 'spec', 'plan', 'build', 'verify', 'review', 'merged'"

  def up do
    rebuild("""
      stage TEXT CHECK (stage IN (#{@stages})),
      slug TEXT,
      born TEXT CHECK (born IN ('operator', 'machine')),
      awaiting TEXT,
    """)
  end

  def down do
    rebuild("""
      stage TEXT,
      slug TEXT,
      born TEXT,
      awaiting TEXT,
    """)
  end

  defp rebuild(workline_columns) do
    execute(fn ->
      repo().checkout(fn ->
        for sql <- statements(workline_columns), do: repo().query!(sql)
      end)
    end)
  end

  defp statements(workline_columns) do
    [
      "PRAGMA foreign_keys = OFF",
      """
      CREATE TABLE thread_new (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
        created_at TEXT NOT NULL,
        agent_id INTEGER REFERENCES agent(id),
        scope TEXT NOT NULL DEFAULT 'project' CHECK (scope IN ('project', 'machine')),
        #{workline_columns}
        world_id INTEGER REFERENCES world(id)
      )
      """,
      """
      INSERT INTO thread_new (id, title, state, created_at, agent_id, scope, stage, slug, born, awaiting, world_id)
      SELECT id, title, state, created_at, agent_id, scope, stage, slug, born, awaiting, world_id FROM thread
      """,
      "DROP TABLE thread",
      "ALTER TABLE thread_new RENAME TO thread",
      "CREATE UNIQUE INDEX thread_slug_index ON thread (slug) WHERE slug IS NOT NULL",
      # DROP TABLE took every old index with it — recreate the staffing lookup's.
      "CREATE INDEX thread_agent_id_index ON thread (agent_id)",
      "PRAGMA foreign_keys = ON"
    ]
  end
end
