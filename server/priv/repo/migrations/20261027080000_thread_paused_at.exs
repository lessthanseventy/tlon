defmodule Server.Repo.Migrations.ThreadPausedAt do
  @moduledoc false
  use Ecto.Migration

  # A thread the operator paused on its own (Server.Pause.pause_thread/1). Not a `state`: a paused
  # thread stays "open" to every query.
  def change do
    alter table(:thread) do
      add :paused_at, :utc_datetime
    end
  end
end
