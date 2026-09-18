defmodule Server.Repo.Migrations.Session do
  use Ecto.Migration

  # 005 session (aleph §3, §9.3). The EPHEMERAL instance of an agent: it runs in a
  # pane, on an engine, on one thread — and it compacts, forgets, and dies (§10).
  # The agent persists; sessions come and go. A session REFERENCES an agent and a
  # thread, both FKs the DB enforces (§10) — an orphan session is refused by SQLite
  # itself, never by a mirrored app check.
  #
  # `workspace_ref` is §2's one seam, written so it cannot be widened: an OPAQUE
  # handle to the Herdr/tmux pane and NEVER a cached copy of its properties — no
  # label, no pane list, no status. Liveness is asked of the arbiter live, within
  # the turn that needs it; the moment a workspace property is stored here, §3 is
  # broken and v1's drift starts again. Nullable — the handle may not be known yet.
  #
  # `ended_at` (nullable) is the only lifecycle we store: NULL = a candidate to
  # jump into, stamped = done. Presence ("clocked out" — credits spent, window
  # closed) is DERIVED from the engine and asked live (§3b), never a column here.
  #
  # Plain SQL: SQLite needs the FKs inline, and a CREATE TABLE a human reads at 2am
  # is the point (§4).
  def change do
    execute(
      """
      CREATE TABLE session (
        id INTEGER PRIMARY KEY,
        agent_id INTEGER NOT NULL REFERENCES agent(id),
        thread_id INTEGER NOT NULL REFERENCES thread(id),
        workspace_ref TEXT,
        started_at TEXT NOT NULL,
        ended_at TEXT
      )
      """,
      "DROP TABLE session"
    )

    # The jump-into-session read path: the newest still-open session for a thread.
    create index(:session, [:thread_id])
  end
end
