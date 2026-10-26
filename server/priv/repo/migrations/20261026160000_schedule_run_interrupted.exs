defmodule Server.Repo.Migrations.ScheduleRunInterrupted do
  @moduledoc false
  use Ecto.Migration

  # A run cut off by a stop or a kill is `interrupted`: neither a pass nor a red.
  def up do
    execute("ALTER TABLE schedule_run DROP CONSTRAINT schedule_run_status_check")

    execute("""
    ALTER TABLE schedule_run ADD CONSTRAINT schedule_run_status_check
      CHECK (status IN ('running', 'ok', 'failed', 'interrupted'))
    """)
  end

  def down do
    execute("UPDATE schedule_run SET status = 'failed' WHERE status = 'interrupted'")
    execute("ALTER TABLE schedule_run DROP CONSTRAINT schedule_run_status_check")

    execute("""
    ALTER TABLE schedule_run ADD CONSTRAINT schedule_run_status_check
      CHECK (status IN ('running', 'ok', 'failed'))
    """)
  end
end
