defmodule Server.Repo.Migrations.Thread do
  use Ecto.Migration

  # 002 thread (aleph §2, §9.2). The atom of work: a subject promoted to a
  # first-class row that `message` — and later `fact`/`event`/`issue` — reference.
  # `title` is the thread's authoritative headline (kept distinct from the fuzzy,
  # non-load-bearing `subject` discovery tag §4 gives `fact`). `state` is a CLOSED
  # two-value set guarded by a database CHECK — §4's discipline against a wide
  # discriminator, in the DB because the DB is the truth (§10); widening it is a
  # migration, which is the point. `created_at` is an ISO-8601 TEXT stamp
  # (ecto_sqlite3 stores :utc_datetime as text); age is never stored, it is
  # computed in the query (§6). The assigned agent and the opaque live session
  # hang off the thread later (step 3) via their own migrations.
  #
  # Written as plain SQL because SQLite cannot ALTER TABLE ADD CONSTRAINT (the
  # CHECK must be inline) — and a CREATE TABLE a human can read at 2am is the point.
  def change do
    execute(
      """
      CREATE TABLE thread (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE thread"
    )
  end
end
