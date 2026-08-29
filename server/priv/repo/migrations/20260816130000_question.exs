defmodule Server.Repo.Migrations.Question do
  use Ecto.Migration

  # 017 question (pi doc §5 slice 4). A knowledge gap in the work — "does raxol support
  # embedding?" — that the dossier surfaces as UNKNOWNS beside FACTS. Knowing what you
  # don't know is first-class (§4a): the doubt is inherited, not just the conclusion.
  #
  # `question` earns its OWN table rather than folding into `issue`, whose identity is
  # now firm (defects in the STACK/tooling, never task work). Folding a task's open
  # questions into the stack's tracker would erode the boundary the same day it was drawn.
  #
  # `resolved_at` is present FROM BIRTH — the same `closed_at` gap recorded against `issue`
  # must not recur. `state` is a CLOSED set the DB CHECKs (open | resolved). `resolution`
  # holds the answer when resolved; a durable answer is then banked as a `fact` (resolvable
  # into a fact), not left only here. thread_id NOT NULL: a task question with no task is
  # meaningless. Plain SQL, CHECK + FK inline, 2am-readable (§4).
  def change do
    execute(
      """
      CREATE TABLE question (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER NOT NULL REFERENCES thread(id),
        text TEXT NOT NULL,
        resolution TEXT,
        state TEXT NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'resolved')),
        resolved_at TEXT,
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE question"
    )

    # orient reads open questions for a thread (UNKNOWNS) at start — the hot path.
    create index(:question, [:thread_id])
  end
end
