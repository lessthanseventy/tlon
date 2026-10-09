defmodule Server.Repo.Migrations.LibrarianEventKinds do
  @moduledoc false
  use Ecto.Migration

  # The librarian's curation keeps its reason where nothing else would: `superseded` (a fact retired
  # by a newer one, by hand) and `forgotten` (a tombstone). `supersede_proposed` is the correction
  # judge's proposal the librarian decides on.
  def change do
    drop constraint(:event, "event_kind_check")

    create constraint(:event, "event_kind_check",
             check: """
             kind IN ('work_landed', 'command_approved', 'check_passed', 'check_failed',
             'handoff_opened', 'cited', 'stage_advanced', 'thread_deleted',
             'superseded', 'forgotten', 'supersede_proposed')
             """
           )
  end
end
