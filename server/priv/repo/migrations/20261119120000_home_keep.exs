defmodule Server.Repo.Migrations.HomeKeep do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:home_keep, primary_key: false) do
      add :name, :string, primary_key: true
      add :body, :text, null: false
    end
  end
end
