defmodule Server.Repo.Migrations.SeatGradeSpecialty do
  @moduledoc false
  use Ecto.Migration

  # A seat's grade is a capability requirement the operator's config maps to a model; its specialty
  # is the area whose facts are scoped to it. Both null on a seat nobody graded.
  def change do
    alter table(:workspace_agent) do
      add :grade, :text
      add :specialty, :text
    end

    create constraint(:workspace_agent, :workspace_agent_grade_check,
             check: "grade in ('junior', 'senior', 'greybeard')"
           )
  end
end
