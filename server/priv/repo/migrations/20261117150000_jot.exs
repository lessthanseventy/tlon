defmodule Server.Repo.Migrations.Jot do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:jot) do
      add :via, :string, null: false
      add :external_id, :bigint, null: false
      add :body, :text, null: false
      add :received_at, :utc_datetime, null: false
    end

    create unique_index(:jot, [:via, :external_id])
  end
end
