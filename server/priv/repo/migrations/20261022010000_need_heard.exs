defmodule Server.Repo.Migrations.NeedHeard do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:need_heard, primary_key: false) do
      add :key, :string, primary_key: true
      add :at, :utc_datetime, null: false
    end
  end
end
