defmodule Server.Repo.Migrations.MessageUndeliveredIndex do
  use Ecto.Migration

  # 013 the drain hot path scans `message WHERE delivered_at IS NULL` on every
  # switchboard start. A PARTIAL index keeps that scan proportional to the pending
  # backlog rather than the whole message history — which matters because a message
  # addressed to no live recipient stays undelivered and is re-scanned each drain.
  # SQLite supports partial indexes.
  def change do
    create index(:message, [:id], where: "delivered_at IS NULL", name: :message_undelivered)
  end
end
