defmodule Server.Repo.Migrations.MessageReplyTo do
  use Ecto.Migration

  # 011 message.reply_to (aleph §2, the addressed-delivery model). A message may be
  # a REPLY to another message on the thread — the third way a message is addressed
  # (top-level → the thread's lead; @mention → a coworker; reply → the replied-to
  # message's author). Nullable self-FK; the FK is the DB's guard (§10). SQLite
  # allows ADD COLUMN with a column-level REFERENCES when nullable.
  def change do
    execute(
      "ALTER TABLE message ADD COLUMN reply_to INTEGER REFERENCES message(id)",
      "ALTER TABLE message DROP COLUMN reply_to"
    )

    create index(:message, [:reply_to])
  end
end
