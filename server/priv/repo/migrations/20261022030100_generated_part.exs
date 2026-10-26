defmodule Server.Repo.Migrations.GeneratedPart do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:generated_part) do
      add :workspace_id, :integer, null: false
      add :day, :date, null: false
      add :slot, :string, null: false
      add :front, :map, null: false
      add :side, :map, null: false
      add :back, :map, null: false
    end

    create unique_index(:generated_part, [:workspace_id, :day])
  end
end
