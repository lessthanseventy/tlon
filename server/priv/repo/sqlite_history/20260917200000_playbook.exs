defmodule Server.Repo.Migrations.Playbook do
  use Ecto.Migration

  # A playbook (2026-09-17, field survey §4 adopt #4 — Devin's Knowledge/Playbooks split, Multica's
  # compound skills): a NAMED procedure with success criteria a coworker can be told to run.
  # FACTS are knowledge (what is true); a playbook is how (steps, in order). `source_thread_id`
  # is the thread it was promoted from, when it was — a solved problem turned into a procedure.
  def change do
    execute(
      """
      CREATE TABLE playbook (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        summary TEXT NOT NULL DEFAULT '',
        steps TEXT NOT NULL,
        success TEXT NOT NULL DEFAULT '',
        author TEXT,
        source_thread_id INTEGER REFERENCES thread(id),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """,
      "DROP TABLE playbook"
    )
  end
end
