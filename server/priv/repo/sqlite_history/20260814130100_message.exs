defmodule Server.Repo.Migrations.Message do
  use Ecto.Migration

  # 003 message (spec §5b, aleph §9.2). The channel, and §4's capture path — a
  # message a participant writes is already a durable row, so intent becomes
  # permanent as a side effect of talking.
  #
  # `thread_id` is required and REFERENCES thread(id): "no required fields beyond a
  # thread and a body" (§5b). There is no ON DELETE cascade — a thread closes, it
  # is not deleted, and history is never taken down with it. `author` is a plain
  # participant handle (the human is a participant too, §5b); it becomes a real
  # `agent` reference in step 3.
  #
  # `delivered_at` exists; a `read` column deliberately does NOT (§5b.3). Day one
  # has nothing that can PROVE a message was read, and "if nothing can prove a
  # message was read, the column does not exist rather than lying." `delivered_at`
  # is written only by the switchboard's delivery path (a later increment) and may
  # only ever mean delivered — never a sender-written receipt that fakes "read".
  #
  # Plain SQL for the same reason as `thread`: SQLite needs the FK inline, and a
  # CREATE TABLE a human can read at 2am is the point (§4).
  def change do
    execute(
      """
      CREATE TABLE message (
        id INTEGER PRIMARY KEY,
        thread_id INTEGER NOT NULL REFERENCES thread(id),
        author TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at TEXT NOT NULL,
        delivered_at TEXT
      )
      """,
      "DROP TABLE message"
    )

    # A thread's messages, in the order they were posted — the hot read path.
    create index(:message, [:thread_id])
  end
end
