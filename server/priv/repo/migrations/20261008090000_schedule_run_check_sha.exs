defmodule Server.Repo.Migrations.ScheduleRunCheckSha do
  @moduledoc false
  use Ecto.Migration

  # A script run that names the commit it checked (`ran-on: <check> <sha>`): "the gate passed on X"
  # is a lookup on these, never an inference from when it ran.
  def change do
    alter table(:schedule_run) do
      add :check_name, :text
      add :sha, :text
    end

    create index(:schedule_run, [:check_name, :sha])
  end
end
