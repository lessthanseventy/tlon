defmodule Server.Repo.Migrations.JotReading do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:jot) do
      add :kind, :string
      add :text, :text
      add :due_at, :utc_datetime
      add :nudged_at, :utc_datetime
    end
  end
end
