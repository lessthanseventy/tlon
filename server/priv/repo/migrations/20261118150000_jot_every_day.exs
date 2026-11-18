defmodule Server.Repo.Migrations.JotEveryDay do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:jot) do
      add :every_day, :integer
    end
  end
end
