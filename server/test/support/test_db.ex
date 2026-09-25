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
    # no FKs either way; schemaless, so by table name. A leftover job or row is counted by the next
    # test that reads the table (all_enqueued, a JSONL export).
    "oban_jobs",
    "collection",
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
    # playbook.source_thread_id → thread, so before Thread
    Server.Playbook,
    Server.Message,
    Server.Session,
    Server.Thread,
    Server.Agent,
    Server.Project,
    # channel.workspace_id → workspace (threads point at channels, so after Thread)
    Server.ChannelRow,
    Server.Workspace
  ]

  @doc """
  Delete every domain row, children before parents — and, when the test exits, wait out the
  background tasks it started (`await_background/0`).
  """
  def clean! do
    ExUnit.Callbacks.on_exit(&await_background/0)
    Enum.each(@ordered, &Repo.delete_all/1)
  end

  @doc """
  Wait out every task under `Server.TaskSupervisor` (the switchboard's opening turn, …). `clean!/0`
  runs it on exit: the test arbiters report to whatever `:test_pid` is set when they fire, so a
  task that outlives its test lands in the next test's mailbox. On exit the old pid still owns it.
  """
  def await_background do
    for pid <- Task.Supervisor.children(Server.TaskSupervisor) do
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, _, _, _} -> :ok
      after
        5_000 -> Process.exit(pid, :kill)
      end
    end

    :ok
  end
end
