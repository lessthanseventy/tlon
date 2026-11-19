defmodule Server.Repo.Migrations.HomeAgenda do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:home_agenda) do
      add :via, :string, null: false
      add :name, :string, null: false
      add :every, :string
      add :every_day, :integer
      add :next_at, :utc_datetime
      add :told_for, :utc_datetime
      add :told_at, :utc_datetime
    end

    create unique_index(:home_agenda, ["via", "lower(name)"], name: :home_agenda_via_name_index)

    alter table(:jot) do
      add :agenda_id, :integer
    end

    create index(:jot, [:agenda_id])
  end
end
