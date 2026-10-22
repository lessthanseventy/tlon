defmodule Server.Repo.Migrations.NeedRouting do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:need_routing, primary_key: false) do
      add :key, :string, primary_key: true
      add :state, :string, null: false
      add :why, :text
      add :recommendation, :text
      add :at, :utc_datetime, null: false
    end
  end
end
