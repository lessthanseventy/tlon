defmodule Server.Repo.Migrations.ThreadGrade do
  use Ecto.Migration

  # the grade the manager staffed a workline at (roster design §6): every stage's lead is picked by it
  def change do
    alter table(:thread) do
      add :grade, :text
    end
  end
end
