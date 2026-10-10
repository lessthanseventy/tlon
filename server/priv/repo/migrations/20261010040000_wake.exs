defmodule Server.Repo.Migrations.Wake do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:wake) do
      add :thread_id, references(:thread, on_delete: :delete_all), null: false
      add :agent, :string, null: false
      add :prompt, :text, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:wake, [:thread_id, :agent])
  end
end
