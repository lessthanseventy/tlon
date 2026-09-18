defmodule Server.Repo.Migrations.Search do
  use Ecto.Migration

  # 022 total recall (design: funes-total-recall, slice A). FTS5 full-text search over the message
  # channel and the fact corpus, so a successor can SEARCH past sessions and the ledger, not only
  # read the curated brief. External-content FTS5 (`content='...'`, `content_rowid='id'`) indexes
  # without duplicating the text; the AFTER INSERT/UPDATE/DELETE triggers keep the index in lockstep
  # with the base table (the `('delete', …)` special insert is FTS5's contentless-delete form); a
  # backfill seeds rows that already exist. FTS5 is compiled into exqlite's SQLite (probed before
  # building). Reads rank by bm25 in `Server.Search`. `Server.Doctor.tables/0` filters the `*_fts*`
  # shadow tables so they don't read as domain tables.
  def up do
    execute("CREATE VIRTUAL TABLE message_fts USING fts5(body, content='message', content_rowid='id')")
    execute("CREATE VIRTUAL TABLE fact_fts USING fts5(text, content='fact', content_rowid='id')")

    execute("""
    CREATE TRIGGER message_ai AFTER INSERT ON message BEGIN
      INSERT INTO message_fts(rowid, body) VALUES (new.id, new.body);
    END
    """)

    execute("""
    CREATE TRIGGER message_ad AFTER DELETE ON message BEGIN
      INSERT INTO message_fts(message_fts, rowid, body) VALUES('delete', old.id, old.body);
    END
    """)

    execute("""
    CREATE TRIGGER message_au AFTER UPDATE ON message BEGIN
      INSERT INTO message_fts(message_fts, rowid, body) VALUES('delete', old.id, old.body);
      INSERT INTO message_fts(rowid, body) VALUES (new.id, new.body);
    END
    """)

    execute("""
    CREATE TRIGGER fact_ai AFTER INSERT ON fact BEGIN
      INSERT INTO fact_fts(rowid, text) VALUES (new.id, new.text);
    END
    """)

    execute("""
    CREATE TRIGGER fact_ad AFTER DELETE ON fact BEGIN
      INSERT INTO fact_fts(fact_fts, rowid, text) VALUES('delete', old.id, old.text);
    END
    """)

    execute("""
    CREATE TRIGGER fact_au AFTER UPDATE ON fact BEGIN
      INSERT INTO fact_fts(fact_fts, rowid, text) VALUES('delete', old.id, old.text);
      INSERT INTO fact_fts(rowid, text) VALUES (new.id, new.text);
    END
    """)

    # Seed the index with rows that already exist (no-ops on a fresh db).
    execute("INSERT INTO message_fts(rowid, body) SELECT id, body FROM message")
    execute("INSERT INTO fact_fts(rowid, text) SELECT id, text FROM fact")
  end

  def down do
    for t <- ~w(message_ai message_ad message_au fact_ai fact_ad fact_au) do
      execute("DROP TRIGGER IF EXISTS #{t}")
    end

    execute("DROP TABLE IF EXISTS message_fts")
    execute("DROP TABLE IF EXISTS fact_fts")
  end
end
