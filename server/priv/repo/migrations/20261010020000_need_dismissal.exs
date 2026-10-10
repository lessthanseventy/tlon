defmodule Server.Repo.Migrations.NeedDismissal do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:need_dismissal, primary_key: false) do
      add :key, :string, primary_key: true
      add :at, :utc_datetime, null: false
    end
  end
end
