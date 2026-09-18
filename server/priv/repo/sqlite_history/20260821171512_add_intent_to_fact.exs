defmodule Server.Repo.Migrations.AddIntentToFact do
  use Ecto.Migration

  def change do
    alter table(:fact) do
      add :intent, :text
    end
  end
end
