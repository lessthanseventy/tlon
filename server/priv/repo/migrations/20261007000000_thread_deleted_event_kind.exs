defmodule Server.Repo.Migrations.ThreadDeletedEventKind do
  @moduledoc false
  use Ecto.Migration

  # delete_thread hard-deletes the row; thread_deleted is the durable record of who, when,
  # and what title — the only trace once the thread itself is gone.
  def change do
    drop constraint(:event, "event_kind_check")

    create constraint(:event, "event_kind_check",
             check: """
             kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed',
             'handoff_opened', 'cited', 'stage_advanced', 'thread_deleted')
             """
           )
  end
end
