defmodule Server.Repo.Migrations.Event do
  use Ecto.Migration

  # 008 event (spec §4, aleph §9.4/§9.5). Append-only, what happened — everything
  # v1 scattered across a handoff log, a mail log, a worklog and three signal files
  # is one table with a `kind`.
  #
  # Three decisions §4 makes here, each stopping a table from becoming a dumping
  # ground:
  #   - `kind` is a CLOSED set with a DB CHECK. The set carries the mechanism kinds
  #     (session started/ended, handoff opened, message sent, command approved,
  #     verification result) AND the one OUTCOME kind review found missing:
  #     `work_landed`, without which nothing answers "what did I do yesterday" once
  #     the worklog is retired (§9.4). Adding a kind is a migration — the point.
  #   - Typed columns for what a surface queries; a JSON `detail` only for what a
  #     human reads. `kind`, `thread_id`, `correlation` and `created_at` are what
  #     surfaces query, so they are columns; `detail` is never queried.
  #   - `correlation` is an EXPLICIT column holding the id of the multi-row
  #     lifecycle a row belongs to (a handoff, an issue) — never inferred from
  #     subject text, the join v1 had to hand-roll over 75 rows of which 5 had an id.
  #
  # `thread_id` is nullable (a lifecycle event need not be scoped). `detail` is a
  # TEXT column holding JSON (ecto_sqlite3 stores :map as a JSON string).
  #
  # Plain SQL: the CHECK and FK inline, 2am-readable (§4).
  def change do
    execute(
      """
      CREATE TABLE event (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER REFERENCES thread(id),
        kind TEXT NOT NULL CHECK (kind IN (
          'session_started', 'session_ended', 'handoff_opened', 'message_sent',
          'command_approved', 'check_passed', 'work_landed'
        )),
        correlation TEXT,
        detail TEXT,
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE event"
    )

    create index(:event, [:thread_id])
    # Correlated lifecycles and "what did I do" both read by these.
    create index(:event, [:correlation])
    create index(:event, [:kind])
  end
end
