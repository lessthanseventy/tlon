defmodule Server.Repo.Migrations.SessionStampedAuthorship do
  @moduledoc false
  use Ecto.Migration

  # The session that wrote a row (#679): set from the connection's identity, never a parameter.
  # Nullable, no backfill: a row from before, a system author's or a pre-register call's is NULL,
  # which renders as "session unknown".
  def change do
    for t <- [:message, :ticket, :event] do
      alter table(t), do: add(:session_id, references(:session, on_delete: :nothing), null: true)
    end
  end
end
