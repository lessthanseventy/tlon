defmodule Server.Repo.Migrations.HotFilterIndexes do
  @moduledoc false
  use Ecto.Migration

  def change do
    create index(:thread, [:workspace_id, :state])
    create index(:ticket, [:workspace_id, :status])
    create index(:ticket, [:project_id])
    create index(:event, [:thread_id, :kind])
    create index(:message, [:thread_id, "id DESC"], name: :message_thread_id_id_desc_index)
  end
end
