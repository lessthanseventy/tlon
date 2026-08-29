defmodule Server.Repo.Migrations.Todo do
  use Ecto.Migration

  # 016 todo (pi doc §5 slice 3, the activity axis). A plan step scoped to a thread:
  # what to do (`text`), and `done_at` — NULL open, a timestamp done.
  #
  # `done_at` is present FROM BIRTH. This is the whole point of the column comment: the
  # `issue` table shipped without a completion time and a review caught the gap
  # ("the closed_at gap already recorded against issue must not recur"). A todo knows
  # how it ends the day it is born.
  #
  # No order column. Order is insertion order (`id`) — NEXT is the first open todo,
  # derived, never a stored `next` (a second answer to ordering the spec cuts §5/§6).
  # Reordering is a later verb if evidence ever demands it, not a field guessed now.
  #
  # thread_id is NOT NULL: a plan step with no thread is meaningless (unlike an `issue`,
  # an unowned finding, which is nullable). Plain SQL, FK inline, 2am-readable (§4).
  def change do
    execute(
      """
      CREATE TABLE todo (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER NOT NULL REFERENCES thread(id),
        text TEXT NOT NULL,
        done_at TEXT,
        created_at TEXT NOT NULL
      )
      """,
      "DROP TABLE todo"
    )

    # orient reads open todos for a thread (TODOS/NEXT) at start — the hot path.
    create index(:todo, [:thread_id])
  end
end
