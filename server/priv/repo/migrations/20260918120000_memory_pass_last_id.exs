defmodule Server.Repo.Migrations.MemoryPassLastId do
  use Ecto.Migration

  # Where the memory pass stopped on a thread (one-brain piece E, slice 2): a column, so the
  # pass is a job with no process memory to lose on a restart.
  def change do
    alter table(:thread) do
      add :memory_pass_last_id, :integer
    end
  end
end
