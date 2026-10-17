defmodule Server.Repo.Migrations.NoteRevision do
  @moduledoc false
  use Ecto.Migration

  # a page a note's edit replaced (`Server.Life.put_dump/3`), so no save is ever the only copy
  def change do
    create table(:note_revision) do
      add :note_id, references(:note, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :created_at, :utc_datetime, null: false
    end

    create index(:note_revision, [:note_id])
  end
end
