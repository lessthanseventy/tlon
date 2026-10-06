defmodule Server.Repo.Migrations.Schedule do
  @moduledoc false
  use Ecto.Migration

  # What the operator schedules (Server.Schedules): an agent run, a workline, or a script, on a
  # cron or once at a time; and each time one fired (the automation board).
  def up do
    execute """
    CREATE TABLE schedule (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CONSTRAINT schedule_kind_check CHECK (kind IN ('agent', 'workline', 'script')),
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      cron TEXT,
      at TIMESTAMPTZ,
      agent TEXT,
      standing BOOLEAN NOT NULL DEFAULT false,
      thread_id BIGINT REFERENCES thread(id) ON DELETE SET NULL,
      dir TEXT,
      enabled BOOLEAN NOT NULL DEFAULT true,
      last_run_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL,
      CONSTRAINT schedule_when_check CHECK ((cron IS NULL) <> (at IS NULL))
    )
    """

    execute "CREATE INDEX schedule_workspace ON schedule (workspace_id)"

    execute """
    CREATE TABLE schedule_run (
      id BIGSERIAL PRIMARY KEY,
      schedule_id BIGINT NOT NULL REFERENCES schedule(id) ON DELETE CASCADE,
      status TEXT NOT NULL CONSTRAINT schedule_run_status_check CHECK (status IN ('running', 'ok', 'failed')),
      exit INTEGER,
      output TEXT,
      thread_id BIGINT REFERENCES thread(id) ON DELETE SET NULL,
      started_at TIMESTAMPTZ NOT NULL,
      finished_at TIMESTAMPTZ
    )
    """

    execute "CREATE INDEX schedule_run_schedule ON schedule_run (schedule_id, id DESC)"
  end

  def down do
    execute "DROP TABLE schedule_run"
    execute "DROP TABLE schedule"
  end
end
