defmodule Server.Repo.Migrations.SessionThinking do
  @moduledoc false
  use Ecto.Migration

  # When the session's harness declared a turn started and has not yet declared it over — durable,
  # so a turn the machine cut off can be picked up again after a restart (Server.Staffing).
  def change do
    alter table(:session) do
      add :thinking_since, :utc_datetime
    end
  end
end
