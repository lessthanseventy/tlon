defmodule Server.Repo.Migrations.ThreadAgent do
  use Ecto.Migration

  # 006 thread.agent_id (aleph §3, §9.3). A thread has 0..1 agent — staffing a
  # thread is a reference on the thread, nullable (unassigned is the norm). The FK
  # is the DB's guard (§10): a bogus agent_id is refused by SQLite. No ON DELETE
  # cascade — an agent is durable, deletion is not the model, and closing a thread
  # never touches the agent.
  #
  # Plain SQL: SQLite's ALTER TABLE ADD COLUMN accepts a column-level REFERENCES
  # only when the column is nullable with no NOT NULL — which is exactly the shape
  # wanted. The down path drops the column (SQLite 3.35+ supports DROP COLUMN).
  def change do
    execute(
      "ALTER TABLE thread ADD COLUMN agent_id INTEGER REFERENCES agent(id)",
      "ALTER TABLE thread DROP COLUMN agent_id"
    )

    create index(:thread, [:agent_id])
  end
end
