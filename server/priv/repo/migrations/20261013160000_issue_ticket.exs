defmodule Server.Repo.Migrations.IssueTicket do
  @moduledoc false
  use Ecto.Migration

  # the ticket that owns an issue's fix (`Server.Dossier.fix_issue/1`); its landing resolves the issue
  def change do
    alter table(:issue) do
      add :ticket_id, references(:ticket, on_delete: :nilify_all)
    end
  end
end
