defmodule Server.Repo.Migrations.KeepUpWarm do
  @moduledoc false
  use Ecto.Migration

  def up do
    create table(:keep_up_warm, primary_key: false) do
      add :name, :string, primary_key: true
      add :body, :text, null: false
    end

    execute "INSERT INTO keep_up_warm (name, body) SELECT name, body FROM home_keep WHERE starts_with(name, 'keep_up:warm:')"
    execute "DELETE FROM home_keep WHERE starts_with(name, 'keep_up:warm:')"
  end

  def down do
    execute "INSERT INTO home_keep (name, body) SELECT name, body FROM keep_up_warm ON CONFLICT DO NOTHING"
    drop table(:keep_up_warm)
  end
end
