defmodule Server.Repo.Migrations.JotOrganize do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:jot) do
      add :project_id, :bigint
      add :plan, {:array, :text}, null: false, default: []
      add :proposed, :text
      add :ask, :string
      add :asked_at, :utc_datetime
      add :waiting_on, :string
      add :mins, :integer
      add :touched_at, :utc_datetime
      add :hidden_until, :utc_datetime
      add :someday_at, :utc_datetime
      add :dropped_at, :utc_datetime
      add :shrunk_at, :utc_datetime
    end

    create index(:jot, [:project_id])
  end
end
