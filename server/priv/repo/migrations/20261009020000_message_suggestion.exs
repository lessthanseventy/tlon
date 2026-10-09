defmodule Server.Repo.Migrations.MessageSuggestion do
  @moduledoc false
  use Ecto.Migration

  # A `suggestion` is a corkboard suggestion (Server.Office.Corkboard) kept on the standing thread:
  # stored delivered, it wakes nobody; resolved when the operator files it or throws it out.
  def up do
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion')"
           )
  end

  def down do
    execute "DELETE FROM message WHERE kind = 'suggestion'"
    drop constraint(:message, :message_kind_check)
    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt', 'stall', 'notice')")
  end
end
