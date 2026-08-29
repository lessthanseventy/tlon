defmodule Server.Repo.Migrations.CitedEventKind do
  use Ecto.Migration

  # Add `cited` to event.kind (forgetting engine, design: docs/plans/2026-08-19-funes-forgetting-design.md):
  # a fact an agent surfaced-and-used earns a positive strength touch, correlated `fact:<id>` like a
  # recheck. SQLite cannot ALTER a CHECK, so the 12-step rebuild — safe because nothing REFERENCES
  # event (it only references thread), so no FK juggling.
  def up,
    do: rebuild("kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened', 'cited')")

  def down,
    do: rebuild("kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened')")

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
