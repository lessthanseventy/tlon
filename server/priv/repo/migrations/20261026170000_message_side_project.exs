defmodule Server.Repo.Migrations.MessageSideProject do
  @moduledoc false
  use Ecto.Migration

  # A `side project` is a seat's running personal project (Server.Office.Corkboard, souls step 4)
  # kept on the workspace's standing thread so its stanza number survives a restart: stored
  # delivered, it wakes nobody.
  def up do
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion', 'margin', 'side project')"
           )
  end

  def down do
    execute "DELETE FROM message WHERE kind = 'side project'"
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion', 'margin')"
           )
  end
end
