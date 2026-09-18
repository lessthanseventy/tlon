defmodule Server.Repo.Migrations.CheckFailedKind do
  use Ecto.Migration

  # 018 add `check_failed` to event.kind (roadmap #5, measured verification). record_check
  # lands a MEASURED outcome — a command's REAL exit code — as `check_passed` (exit 0) or
  # `check_failed`, so an agent's "it works" stops being self-reported (the spec's cardinal
  # claim: a claim that something works is backed by having run it). `check_passed` was born
  # with the narrowed set (010 event_kinds); `check_failed` is its missing half.
  #
  # SQLite cannot ALTER a CHECK, so this is the 12-step table rebuild — safe because nothing
  # REFERENCES event (it only references thread), so no FK juggling. The copy is written to
  # be correct even though the table is small in practice.
  def up,
    do: rebuild("kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed', 'handoff_opened')")

  def down, do: rebuild("kind IN ('work_landed', 'command_approved', 'check_passed', 'handoff_opened')")

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
