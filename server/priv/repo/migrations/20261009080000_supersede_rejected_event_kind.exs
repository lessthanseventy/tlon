defmodule Server.Repo.Migrations.SupersedeRejectedEventKind do
  @moduledoc false
  use Ecto.Migration

  # A judged supersede is a model's call, so its reason is kept (Server.Recall.Supersede.judged/5);
  # a proposal a reviewer turns down is closed as supersede_rejected, with why.
  def change do
    drop constraint(:event, "event_kind_check")

    create constraint(:event, "event_kind_check",
             check: """
             kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed',
             'handoff_opened', 'cited', 'stage_advanced', 'thread_deleted',
             'superseded', 'forgotten', 'supersede_proposed', 'supersede_rejected')
             """
           )
  end
end
