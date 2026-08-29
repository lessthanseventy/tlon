defmodule Server.Repo.Migrations.ConsultIdIndex do
  use Ecto.Migration

  # `Consult.find_ask/1` filters `consult_id == ^id and mirrored == false` on every consult
  # reply; without an index that is a full message-table scan that grows with history. Partial
  # on the un-mirrored side — mirrored copies are never looked up by consult_id.
  def change do
    create index(:message, [:consult_id], where: "mirrored = 0")
  end
end
