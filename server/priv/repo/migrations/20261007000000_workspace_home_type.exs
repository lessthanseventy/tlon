defmodule Server.Repo.Migrations.WorkspaceHomeType do
  @moduledoc false
  use Ecto.Migration

  # home joins code|life|blank (life step 4): the life side's workspace kind.
  def up do
    execute "ALTER TABLE workspace DROP CONSTRAINT workspace_type_check"
    execute "ALTER TABLE workspace ADD CONSTRAINT workspace_type_check CHECK (type IN ('code','life','blank','home'))"
  end

  def down do
    execute "ALTER TABLE workspace DROP CONSTRAINT workspace_type_check"
    execute "ALTER TABLE workspace ADD CONSTRAINT workspace_type_check CHECK (type IN ('code','life','blank'))"
  end
end
