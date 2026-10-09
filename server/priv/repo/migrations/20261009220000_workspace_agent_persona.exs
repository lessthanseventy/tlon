defmodule Server.Repo.Migrations.WorkspaceAgentPersona do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:workspace_agent) do
      add :persona, :map
    end
  end
end
