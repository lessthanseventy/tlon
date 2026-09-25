defmodule Server.Repo.Migrations.MessagePrompts do
  @moduledoc false
  use Ecto.Migration

  # A coworker waiting on the operator is a `prompt` message (Server.Attention): the dialog's
  # options in `payload`, and how it ended in `resolved_at`/`resolution`.
  def change do
    alter table(:message) do
      add :kind, :text, null: false, default: "chat"
      add :payload, :jsonb
      add :resolved_at, :utc_datetime
      add :resolution, :text
    end

    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt')")

    create index(:message, [:thread_id],
             where: "kind = 'prompt' and resolved_at is null",
             name: :message_open_prompt_index
           )
  end
end
