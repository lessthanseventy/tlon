defmodule Server.Repo.Migrations.MessageMargin do
  @moduledoc false
  use Ecto.Migration

  # A `margin` is one of Uqbar's one-line margin notes (docs/plans/2026-10-08-uqbar-design.md §4)
  # kept on the workspace's root thread: stored delivered, it wakes nobody; the office draws it.
  def up do
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion', 'margin')"
           )
  end

  def down do
    execute "DELETE FROM message WHERE kind = 'margin'"
    drop constraint(:message, :message_kind_check)

    create constraint(:message, :message_kind_check,
             check: "kind in ('chat', 'prompt', 'stall', 'notice', 'suggestion')"
           )
  end
end
