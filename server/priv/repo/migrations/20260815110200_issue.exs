defmodule Server.Repo.Migrations.Issue do
  use Ecto.Migration

  # 009 issue (spec §5, aleph §9.4). A finding that outlives the session that found
  # it — the table whose absence nearly evaporated three findings in one day, and
  # where two thirds of v1's "constraints" actually belonged (they were in-flight
  # work that expired, not durable knowledge).
  #
  # An issue is what was found (`summary`), where the evidence is (`evidence`), what
  # would settle it (`resolution`), who found it (`found_by`), and its `state` — a
  # CLOSED set the DB CHECKs (open | closed). Deliberately ticket-shaped and LOCAL:
  # about this machine's own defects, never product work. `thread_id` is nullable —
  # an unowned finding scoped to nothing is visible only in the coordination
  # surface (§5), so it must be storable without a subject.
  #
  # Scope note (§5): issues are read "for a subject and repository". Here the
  # subject is the thread; a repository scope is not a column yet — it is added when
  # a surface needs it, not before (don't-over-build). `summary` is the only
  # required field: any participant may raise anything (§5b generality).
  #
  # Plain SQL: the CHECK and FK inline, 2am-readable (§4).
  def change do
    execute(
      """
      CREATE TABLE issue (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER REFERENCES thread(id),
        summary TEXT NOT NULL,
        evidence TEXT,
        resolution TEXT,
        found_by TEXT,
        state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'closed')),
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE issue"
    )

    # orient reads open issues for a thread at start — the hot path.
    create index(:issue, [:thread_id])
  end
end
