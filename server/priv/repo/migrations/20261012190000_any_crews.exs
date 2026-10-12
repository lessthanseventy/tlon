defmodule Server.Repo.Migrations.AnyCrews do
  @moduledoc false
  use Ecto.Migration

  # Crews are named by the operator, as many as it likes (`Server.Shifts`); the changeset checks a name.
  def up do
    drop constraint(:workspace_agent, :workspace_agent_crew_check)
    drop constraint(:workspace, :workspace_shift_check)
  end

  def down do
    create constraint(:workspace_agent, :workspace_agent_crew_check, check: "crew IN ('all', 'day', 'night')")
    create constraint(:workspace, :workspace_shift_check, check: "shift IN ('day', 'night')")
  end
end
