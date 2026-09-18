defmodule Server.Repo.Migrations.FactForgottenAt do
  use Ecto.Migration

  # The operator's manual tombstone — set means the fact is out of every recall
  # surface (dossier, floor, search, embedding) but the row and its provenance stay.
  def change do
    alter table(:fact) do
      add :forgotten_at, :utc_datetime
    end
  end
end
