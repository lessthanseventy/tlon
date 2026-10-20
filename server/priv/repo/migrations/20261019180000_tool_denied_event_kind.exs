defmodule Server.Repo.Migrations.ToolDeniedEventKind do
  @moduledoc false
  use Ecto.Migration

  # A tool call refused by a seat's permission check (`tool_denied` MCP verb): the fact the operator's
  # `tool_denied` Need is derived from (`Server.Office.Needs`).
  def change do
    drop constraint(:event, "event_kind_check")

    create constraint(:event, "event_kind_check",
             check: """
             kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed',
             'handoff_opened', 'cited', 'stage_advanced', 'thread_deleted',
             'superseded', 'forgotten', 'supersede_proposed', 'supersede_rejected', 'tool_denied')
             """
           )
  end
end
