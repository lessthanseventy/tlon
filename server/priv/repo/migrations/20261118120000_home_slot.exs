defmodule Server.Repo.Migrations.HomeSlot do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:home_slot, primary_key: false) do
      add :name, :string, primary_key: true
      add :slot, :date, null: false
      add :setting, :string, null: false
    end
  end
end
