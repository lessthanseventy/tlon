defmodule Server.Repo.Migrations.EventKinds do
  use Ecto.Migration

  # 010 narrow event.kind (spec §4, amended 2026-08-15). `event` holds only
  # happenings with NO OTHER HOME. Migration 008 born it with the derivable kinds
  # in its CHECK — `session_started`, `session_ended`, `message_sent` — but those
  # each already leave their own row (`session`, `message`) with their own
  # timestamp. A `message_sent` event is a second source for "when it happened"
  # (§2) and a dual write (§10), the exact defect that retired the `turn` table. So
  # the "what happened" timeline DERIVES those from their own rows; `event` keeps
  # only the outcomes and judgements no other table records:
  #   work_landed · command_approved · check_passed · handoff_opened
  #
  # SQLite cannot ALTER a CHECK, so this is the 12-step table rebuild — safe here
  # because nothing REFERENCES event (it only references thread), so no FK juggling
  # is needed. The table is empty in practice (nothing emits events yet), but the
  # copy is written to be correct regardless.
  def up, do: rebuild(homeless_kinds())
  def down, do: rebuild(original_kinds())

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

  defp homeless_kinds,
    do: "kind IN ('work_landed', 'command_approved', 'check_passed', 'handoff_opened')"

  defp original_kinds,
    do: """
    kind IN (
      'session_started', 'session_ended', 'handoff_opened', 'message_sent',
      'command_approved', 'check_passed', 'work_landed'
    )
    """
end
