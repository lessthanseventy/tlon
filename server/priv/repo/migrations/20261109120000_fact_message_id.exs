defmodule Server.Repo.Migrations.FactMessageId do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:fact) do
      add :message_id, references(:message, on_delete: :nilify_all)
    end
  end
end
