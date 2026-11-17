defmodule Server.Repo.Migrations.JotDone do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:jot) do
      add :done_at, :utc_datetime
      add :nudges, :integer, null: false, default: 0
    end
  end
end
