defmodule Server.Repo.Migrations.ToyPoolAndGeneratorCalls do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:toy_pool) do
      add :workspace_id, :integer, null: false
      add :key, :string, null: false
      add :items, :map, null: false
      add :seed, :integer, null: false
      add :generated_at, :utc_datetime, null: false
    end

    create unique_index(:toy_pool, [:workspace_id, :key])

    create table(:generator_call, primary_key: false) do
      add :day, :date, primary_key: true
      add :calls, :integer, null: false, default: 0
    end
  end
end
