defmodule Server.Repo.Migrations.PaneRetiredEventKind do
  @moduledoc false
  use Ecto.Migration

  # A coworker's pane closed between turns by the server (a stale launch, a stuck seat's roll): what
  # the next session there is told when it opens (`Server.Staffing.left_off/2`).
  def change do
    drop constraint(:event, "event_kind_check")

    create constraint(:event, "event_kind_check",
             check: """
             kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed',
             'handoff_opened', 'cited', 'stage_advanced', 'thread_deleted',
             'superseded', 'forgotten', 'supersede_proposed', 'supersede_rejected', 'tool_denied',
             'pane_retired')
             """
           )
  end
end
