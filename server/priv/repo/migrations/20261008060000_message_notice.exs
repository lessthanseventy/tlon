defmodule Server.Repo.Migrations.MessageNotice do
  @moduledoc false
  use Ecto.Migration

  # A `notice` is the server telling a thread something (a restart) that wakes nobody: its workers
  # read it on their next turn.
  def up do
    drop constraint(:message, :message_kind_check)
    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt', 'stall', 'notice')")
  end

  def down do
    execute "DELETE FROM message WHERE kind = 'notice'"
    drop constraint(:message, :message_kind_check)
    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt', 'stall')")
  end
end
