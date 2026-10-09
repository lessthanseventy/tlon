defmodule Server.Repo.Migrations.TwoCrews do
  @moduledoc false
  use Ecto.Migration

  # A seat is on the day shift, the night shift, or both (`all`, so a bench with no shifts set is
  # unchanged). The workspace is on one shift at a time.
  def change do
    alter table(:workspace_agent) do
      add :crew, :text, null: false, default: "all"
    end

    create constraint(:workspace_agent, :workspace_agent_crew_check, check: "crew IN ('all', 'day', 'night')")

    alter table(:workspace) do
      add :shift, :text, null: false, default: "day"
    end

    create constraint(:workspace, :workspace_shift_check, check: "shift IN ('day', 'night')")
  end
end
