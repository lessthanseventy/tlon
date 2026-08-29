defmodule Server.Repo.Migrations.Fact do
  use Ecto.Migration

  # 007 fact (spec §4, aleph §9.4). Durable things learned — the successor to v1's
  # ledger, and the judgement half a system cannot derive. One fact, one claim, one
  # provenance (§4): a row is a single claim, so provenance can be a property of it.
  #
  # `kind` is a CLOSED set guarded by a DB CHECK — decision | constraint | learned.
  # `provenance` is a CLOSED set — stated (the owner said it, quoted verbatim) |
  # derived (we produced it). A third value 'measured' was proposed and REJECTED
  # (§4): it returned a false zero and never carried the property anyone wanted.
  # Both CHECKs are the DB's own guard (§10), never mirrored app-side.
  #
  # Reproducibility is a SEPARATE axis from provenance, so it is its own column:
  # `check_cmd` holds the command that re-runs the claim (spec's `check`, renamed
  # to dodge SQLite's reserved word so the schema stays 2am-greppable). The total
  # order is stated > derived WITH a check > derived WITHOUT — and
  # `provenance='derived' AND check_cmd IS NULL` names our unverifiable opinions,
  # the set that must rank lowest.
  #
  # Edges are `supersedes` and `taught` only (§ "Settled"), no general edge table.
  # `supersedes` REFERENCES fact(id): superseding is EXPLICIT, never inferred from
  # recency — a fact something supersedes is retired (one mechanism, not a second
  # `state` column that could disagree, §2). `taught` names where a fact was
  # promoted into a rule (AGENTS.md, a skill); NULL = not yet taught, which doctor
  # counts (§7). `incident` is the failure that produced it; `source_session_id`
  # REFERENCES session(id) — who banked it, nullable (an external session may not
  # be registered). `thread_id` is nullable: the always-loaded constraints are
  # machine-wide, not scoped to any thread.
  #
  # Plain SQL: SQLite needs the CHECKs and FKs inline, and a CREATE TABLE a human
  # reads at 2am is the point (§4).
  def change do
    execute(
      """
      CREATE TABLE fact (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER REFERENCES thread(id),
        kind TEXT NOT NULL CHECK (kind IN ('decision', 'constraint', 'learned')),
        text TEXT NOT NULL,
        provenance TEXT NOT NULL CHECK (provenance IN ('stated', 'derived')),
        check_cmd TEXT,
        incident TEXT,
        supersedes INTEGER REFERENCES fact(id),
        taught TEXT,
        source_session_id INTEGER REFERENCES session(id),
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE fact"
    )

    create index(:fact, [:thread_id])
    # The 'is this superseded?' subquery in always_loaded_constraints reads this.
    create index(:fact, [:supersedes])
  end
end
