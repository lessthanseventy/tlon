defmodule Server.Repo.Migrations.ThreadWorkline do
  use Ecto.Migration

  # Worklines slice 1: a thread can BE a workline — stage machine state + the git-folder slug
  # + who authored the intent + the parked-gate marker + the world it belongs to. All nullable:
  # a plain thread is untouched. `slug` names `work/<slug>/` so it must be unique among the living.
  def change do
    alter table(:thread) do
      add :stage, :text
      add :slug, :text
      add :born, :text
      add :awaiting, :text
      add :world_id, references(:world)
    end

    create unique_index(:thread, [:slug], where: "slug IS NOT NULL")
  end
end
