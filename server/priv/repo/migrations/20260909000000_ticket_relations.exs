defmodule Server.Repo.Migrations.TicketRelations do
  @moduledoc false
  use Ecto.Migration

  # Tickets done properly (UX slice 4, 2026-09-08): a ticket stops being an island.
  #
  # `ticket_link` — ticket→ticket. `blocks | relates | duplicates | parent`, stored ONE way and
  # read both: "blocked by" is the inverse of `blocks`, never a second row, so the two can never
  # disagree. A ticket cannot link to itself, and a pair cannot carry the same kind twice.
  #
  # `ticket_thread` — the many-to-many the single `promoted_thread_id` column could not express: a
  # ticket may be discussed in several threads, a thread may carry several tickets, and either can
  # live alone. `promoted` is one KIND of tie, so the old column's data becomes a `promoted` row
  # and the column goes — one place a tie is recorded, not two.
  #
  # `sort` orders a ticket within its status column so the board's order survives a restart
  # (`order` is a SQL keyword). `closed_at` stamps when a ticket reached `done`; the backfill
  # uses `updated_at`, which is the closest thing already on disk.
  def up do
    execute("""
    CREATE TABLE ticket_link (
      id INTEGER PRIMARY KEY,
      from_id INTEGER NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      to_id INTEGER NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('blocks','relates','duplicates','parent')),
      created_at TEXT NOT NULL,
      CHECK (from_id <> to_id),
      UNIQUE (from_id, to_id, kind)
    )
    """)

    execute("""
    CREATE TABLE ticket_thread (
      id INTEGER PRIMARY KEY,
      ticket_id INTEGER NOT NULL REFERENCES ticket(id) ON DELETE CASCADE,
      thread_id INTEGER NOT NULL REFERENCES thread(id) ON DELETE CASCADE,
      kind TEXT NOT NULL DEFAULT 'relates' CHECK (kind IN ('promoted','relates')),
      created_at TEXT NOT NULL,
      UNIQUE (ticket_id, thread_id, kind)
    )
    """)

    execute("ALTER TABLE ticket ADD COLUMN sort INTEGER NOT NULL DEFAULT 0")
    execute("ALTER TABLE ticket ADD COLUMN closed_at TEXT")

    # every existing promotion becomes the tie it always was
    execute("""
    INSERT INTO ticket_thread (ticket_id, thread_id, kind, created_at)
    SELECT id, promoted_thread_id, 'promoted', strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
    FROM ticket WHERE promoted_thread_id IS NOT NULL
    """)

    execute("ALTER TABLE ticket DROP COLUMN promoted_thread_id")

    # seed the board order from what the board already showed (newest-first, by id)
    execute("UPDATE ticket SET sort = id")
    execute("UPDATE ticket SET closed_at = updated_at WHERE status = 'done'")

    execute("CREATE INDEX ticket_link_from ON ticket_link (from_id)")
    execute("CREATE INDEX ticket_link_to ON ticket_link (to_id)")
    execute("CREATE INDEX ticket_thread_ticket ON ticket_thread (ticket_id)")
    execute("CREATE INDEX ticket_thread_thread ON ticket_thread (thread_id)")
  end

  def down do
    execute("ALTER TABLE ticket ADD COLUMN promoted_thread_id INTEGER REFERENCES thread(id)")

    execute("""
    UPDATE ticket SET promoted_thread_id = (
      SELECT tt.thread_id FROM ticket_thread tt WHERE tt.ticket_id = ticket.id AND tt.kind = 'promoted'
    )
    """)

    execute("ALTER TABLE ticket DROP COLUMN closed_at")
    execute("ALTER TABLE ticket DROP COLUMN sort")
    execute("DROP TABLE ticket_thread")
    execute("DROP TABLE ticket_link")
  end
end
