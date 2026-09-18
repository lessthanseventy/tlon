defmodule Server.Repo.Migrations.Habit do
  use Ecto.Migration

  # 021 habit — the third memory axis beside FACTS (memory) and skills (procedures):
  # how the agent should WORK with the operator. A habit is agent-PROPOSED and human-
  # APPROVED, which is what distinguishes it from a `stated` constraint (his verbatim
  # words, provenance='stated'): a habit is the machine's suggestion, promoted into the
  # always-loaded set only by his approval. Machine-wide, like the constraints it sits
  # beside — served by Resource.Habits every session, not a per-thread board lane.
  #
  # `state` is a CLOSED set the DB CHECKs (pending | approved | rejected). `approved_at`
  # is present FROM BIRTH — the same completion-time gap recorded against `issue` must not
  # recur. `source_thread_id` is nullable (a habit outlives the thread that proposed it and
  # need not have one) and records provenance — WHICH thread suggested it — never scope.
  # `proposed_by` is the proposing agent (the model). Plain SQL, CHECK + FK inline (§4).
  def change do
    execute(
      """
      CREATE TABLE habit (
        id INTEGER PRIMARY KEY,
        text TEXT NOT NULL,
        rationale TEXT,
        state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'approved', 'rejected')),
        proposed_by TEXT NOT NULL,
        source_thread_id INTEGER REFERENCES thread(id),
        approved_at TEXT,
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE habit"
    )

    # The hot reads are by state: the always-loaded approved set every session reads, and
    # the operator's pending review queue.
    create index(:habit, [:state])
  end
end
