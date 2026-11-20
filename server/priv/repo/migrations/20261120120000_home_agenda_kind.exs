defmodule Server.Repo.Migrations.HomeAgendaKind do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:home_agenda) do
      add :kind, :string, null: false, default: "agenda"
      add :birthday, :string
    end

    drop unique_index(:home_agenda, ["via", "lower(name)"], name: :home_agenda_via_name_index)
    create unique_index(:home_agenda, ["via", "kind", "lower(name)"], name: :home_agenda_via_name_index)
  end
end
