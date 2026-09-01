defmodule Server.Repo.Migrations.ThreadParentId do
  use Ecto.Migration

  # Additive (lead-as-manager, Slice 4D): a thread gains an optional self-referential
  # `parent_thread_id` — set when a lead opens a CHILD thread, nil for top-level threads.
  # No backfill; existing threads stay parentless. Unlink-not-cascade is enforced in
  # `Server.Channel` (a deleted parent's children are unlinked, like facts/issues), not by
  # ON DELETE here. SQLite allows a REFERENCES clause on a freshly-added column.
  def change do
    execute(
      "ALTER TABLE thread ADD COLUMN parent_thread_id INTEGER REFERENCES thread(id)",
      "ALTER TABLE thread DROP COLUMN parent_thread_id"
    )
  end
end
