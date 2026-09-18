defmodule Server.Repo.Migrations.StageEventKind do
  use Ecto.Migration

  # Add `stage_advanced` to event.kind (worklines slice 1): every completed stage flip is a
  # timestamped event, so the slice-6 ledger reads metrics out of rows that already exist.
  # Same 12-step rebuild as the cited migration — SQLite cannot ALTER a CHECK.
  def up,
    do:
      rebuild(
        "kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened', 'cited', 'stage_advanced')"
      )

  def down,
    do: rebuild("kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened', 'cited')")

  defp rebuild(kind_check) do
    execute("""
    CREATE TABLE event_new (
      id INTEGER PRIMARY KEY,
      thread_id INTEGER REFERENCES thread(id),
      kind TEXT NOT NULL CHECK (#{kind_check}),
      correlation TEXT,
      detail TEXT,
      created_at TEXT NOT NULL
    )
    """)

    execute("INSERT INTO event_new SELECT id, thread_id, kind, correlation, detail, created_at FROM event")
    execute("DROP TABLE event")
    execute("ALTER TABLE event_new RENAME TO event")

    create index(:event, [:thread_id])
    create index(:event, [:correlation])
    create index(:event, [:kind])
  end
end
