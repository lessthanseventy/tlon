defmodule Server.TestDB do
  @moduledoc """
  FK-safe truncation for the shared test database. The suite runs against one DB
  with no sandbox, so each test clears the domain rows first — and the order is
  load-bearing: children before parents, or a `delete_all` trips a foreign key. One
  helper so a new suite (or a reordering of them) can't reintroduce the ordering bug
  a review caught, where cleanups deleted `thread` while `fact`/`event`/`issue` still
  referenced it and only passed because the suite that made those rows ran last.
  """
  alias Server.Repo

  # fact → thread+session, event/issue/message/habit → thread, session → agent+thread,
  # thread → agent AND workspace AND project (2026-08-30). project → workspace. So: the leaf
  # rows, then message/session, then thread, then project, then its parents agent + workspace.
  # habit.source_thread_id → thread, so it clears with the other thread-children.
  @ordered [
    # ticket.promoted_thread_id → thread, .project_id → project, .workspace_id → workspace, so
    # tickets clear before all of them; note has no FK.
    Server.Ticket,
    Server.Note,
    Server.Fact,
    Server.Event,
    Server.Issue,
    Server.Todo,
    Server.Question,
    Server.Habit,
    Server.Message,
    Server.Session,
    Server.Thread,
    Server.Agent,
    Server.Project,
    Server.Workspace
  ]

  @doc "Delete every domain row, children before parents."
  def clean! do
    Enum.each(@ordered, &Repo.delete_all/1)
  end
end
