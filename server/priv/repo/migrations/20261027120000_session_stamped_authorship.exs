defmodule Server.Repo.Migrations.SessionStampedAuthorship do
  @moduledoc false
  use Ecto.Migration

  # The session that wrote a row (#679): set from the connection's identity, never a parameter.
  # Nullable, no backfill: a row from before, a system author's or a pre-register call's is NULL,
  # which renders as "session unknown". Nilified when the session goes: a thread's purge deletes its
  # sessions, and their tickets, events and posts on other threads outlive it.
  def change do
    for t <- [:message, :ticket, :event] do
      alter table(t), do: add(:session_id, references(:session, on_delete: :nilify_all), null: true)
    end
  end
end
