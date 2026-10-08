defmodule Server.Repo.Migrations.Life do
  @moduledoc false
  use Ecto.Migration

  # The life side's two rows (life step 4, spec §2): a recurring routine and its runs (the only
  # thing written when it's done), and a one-off quest. xp/level/streak are views — nothing here.
  def up do
    execute """
    CREATE TABLE routine (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      every TEXT NOT NULL,
      window_minutes INTEGER NOT NULL DEFAULT 60,
      xp INTEGER NOT NULL DEFAULT 10,
      tile TEXT,
      enabled BOOLEAN NOT NULL DEFAULT true,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX routine_workspace ON routine (workspace_id)"

    execute """
    CREATE TABLE routine_run (
      id BIGSERIAL PRIMARY KEY,
      routine_id BIGINT NOT NULL REFERENCES routine(id) ON DELETE CASCADE,
      due_at TIMESTAMPTZ NOT NULL,
      done_at TIMESTAMPTZ NOT NULL,
      late BOOLEAN NOT NULL,
      created_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX routine_run_routine ON routine_run (routine_id, due_at DESC)"

    execute """
    CREATE TABLE quest (
      id BIGSERIAL PRIMARY KEY,
      workspace_id BIGINT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      due_at TIMESTAMPTZ,
      xp INTEGER NOT NULL DEFAULT 10,
      done_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL
    )
    """

    execute "CREATE INDEX quest_workspace ON quest (workspace_id)"
  end

  def down do
    execute "DROP TABLE quest"
    execute "DROP TABLE routine_run"
    execute "DROP TABLE routine"
  end
end
