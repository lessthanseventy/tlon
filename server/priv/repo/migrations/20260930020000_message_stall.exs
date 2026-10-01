defmodule Server.Repo.Migrations.MessageStall do
  @moduledoc false
  use Ecto.Migration

  # A coworker mid-turn whose pane has frozen is a `stall` message (Server.Attention.Stall),
  # resolved like a prompt when the pane moves.
  def up do
    drop constraint(:message, :message_kind_check)
    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt', 'stall')")
  end

  def down do
    drop constraint(:message, :message_kind_check)
    create constraint(:message, :message_kind_check, check: "kind in ('chat', 'prompt')")
  end
end
