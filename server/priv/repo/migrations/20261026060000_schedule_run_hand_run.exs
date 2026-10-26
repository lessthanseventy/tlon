defmodule Server.Repo.Migrations.ScheduleRunHandRun do
  @moduledoc false
  use Ecto.Migration

  # A gate or smoke run by hand reports its `ran-on` result with no schedule behind it
  # (`Server.Release.Candidate.record/3`); the automation board lists runs by schedule, so these stay off it.
  def up, do: execute("ALTER TABLE schedule_run ALTER COLUMN schedule_id DROP NOT NULL")

  def down do
    execute("DELETE FROM schedule_run WHERE schedule_id IS NULL")
    execute("ALTER TABLE schedule_run ALTER COLUMN schedule_id SET NOT NULL")
  end
end
