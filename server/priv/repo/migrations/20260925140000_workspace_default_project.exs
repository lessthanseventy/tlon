defmodule Server.Repo.Migrations.WorkspaceDefaultProject do
  @moduledoc false
  use Ecto.Migration

  # The project a thread lands on when nothing picked one, named on the workspace. It used to be
  # found BY NAME ("general"), so renaming that project minted a new "general" on the next boot.
  def up do
    alter table(:workspace) do
      add :default_project_id, references(:project, on_delete: :nilify_all)
    end

    execute """
    update workspace w set default_project_id =
      (select p.id from project p where p.workspace_id = w.id and p.name = 'general' order by p.id limit 1)
    """
  end

  def down do
    alter table(:workspace) do
      remove :default_project_id
    end
  end
end
