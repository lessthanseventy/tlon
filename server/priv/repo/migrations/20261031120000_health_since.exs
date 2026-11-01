defmodule Server.Repo.Migrations.HealthSince do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:health_since, primary_key: false) do
      add :what, :string, primary_key: true
      add :since, :utc_datetime, null: false
    end
  end
end
