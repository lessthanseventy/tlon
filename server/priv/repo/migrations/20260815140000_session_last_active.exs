defmodule Server.Repo.Migrations.SessionLastActive do
  use Ecto.Migration

  # 012 session.last_active_at (aleph §3b, the warmth window). Presence's concrete
  # half: a session is *warm* — cheap to resume — only while its context is still in
  # the prompt cache (~1h). Past that it is COLD and must not be woken, or a poke
  # pays a full transcript re-ingestion (the "resumed a thread and burned my whole
  # allotment" footgun). Warmth is time since the session last ran a turn, so we
  # stamp `last_active_at` and the switchboard bumps it as the session acts.
  #
  # Explicit up/down rather than `change/0`: the backfill is a one-way data step with
  # no meaningful inverse, and rollback just drops the column (which moots it). The
  # index is dropped before the column so `DROP COLUMN` does not trip over it.
  def up do
    execute("ALTER TABLE session ADD COLUMN last_active_at TEXT")
    execute("UPDATE session SET last_active_at = started_at WHERE last_active_at IS NULL")
    create index(:session, [:last_active_at])
  end

  def down do
    drop index(:session, [:last_active_at])
    execute("ALTER TABLE session DROP COLUMN last_active_at")
  end
end
