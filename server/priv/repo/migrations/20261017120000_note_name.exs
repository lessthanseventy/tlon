defmodule Server.Repo.Migrations.NoteName do
  @moduledoc false
  use Ecto.Migration

  # a named note is the one page of its kind in a scope (`Server.Life.dump/1`'s "dump")
  def change do
    alter table(:note) do
      add :name, :text
    end

    create unique_index(:note, [:scope, :scope_id, :name], where: "name IS NOT NULL")
  end
end
