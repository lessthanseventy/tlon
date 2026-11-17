defmodule Server.Repo.Migrations.JotEvery do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:jot) do
      add :every, :string
    end
  end
end
