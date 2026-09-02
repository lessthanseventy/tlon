defmodule Server.BoardSidebarTest do
  # Reshape slice C: the sidebar read-model — per workspace, ONE unified thread list
  # (chat threads and tracked threads are the same kind of row) plus the crew with
  # working flags. The contract the Slack-shaped UI sits on.
  use ExUnit.Case, async: false

  alias Server.Board
  alias Server.Bootstrap
  alias Server.Channel
  alias Server.Presence.Thinking
  alias Server.Workline
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    Thinking.sweep()
    :ok
  end

  test "groups open threads under their workspace; chat and tracked rows unify" do
    {:ok, workspace} = Bootstrap.ensure()
    {:ok, chat} = Channel.open_thread(%{title: "a chat thread"})
    {:ok, tracked} = Workline.open(%{title: "a tracked one", slug: "tracked-one"})

    assert [%{workspace: %{id: workspace_id, name: "ficciones"}, threads: threads}] = Board.sidebar()
    assert workspace_id == workspace.id

    by_id = Map.new(threads, &{&1.id, &1})
    assert %{stage: nil, title: "a chat thread"} = by_id[chat.id]
    assert %{stage: "intent", title: "a tracked one"} = by_id[tracked.id]
  end

  test "the root machine thread sorts first and is flagged" do
    # Bootstrap now guarantees a per-workspace machine root — no need to hand-open one.
    {:ok, workspace} = Bootstrap.ensure()
    {:ok, _chat} = Channel.open_thread(%{title: "newer chat"})
    root = Channel.machine_thread(workspace.id)
    assert root

    [%{threads: [first | _]}] = Board.sidebar()
    assert first.id == root.id
    assert first.root == true
  end

  test "closed threads are omitted; a second workspace gets its own group" do
    {:ok, _default} = Bootstrap.ensure()
    {:ok, other} = Workspaces.register(%{name: "otherland", type: "code", scope: "project", paths: [], roster: []})
    {:ok, housed} = Channel.open_thread(%{title: "in otherland", workspace_id: other.id})
    {:ok, closed} = Channel.open_thread(%{title: "done already"})
    {:ok, _} = Channel.close_thread(closed)

    groups = Board.sidebar()

    assert [
             %{workspace: %{name: "ficciones"}, threads: default_threads},
             %{workspace: %{name: "otherland"}, threads: other_threads}
           ] = groups

    refute Enum.any?(default_threads, &(&1.id == closed.id))
    assert [%{id: housed_id}] = other_threads
    assert housed_id == housed.id
  end

  test "threads order by newest activity after the root" do
    {:ok, workspace} = Bootstrap.ensure()
    root = Channel.machine_thread(workspace.id)
    {:ok, older} = Channel.open_thread(%{title: "older but recently active"})
    {:ok, newer} = Channel.open_thread(%{title: "newer but quiet"})
    {:ok, _} = Channel.post(%{thread_id: older.id, author: "andrew", body: "still on this one"})

    [%{threads: threads}] = Board.sidebar()
    # The root leads (it's flagged root), then the rest by newest activity.
    assert Enum.map(threads, & &1.id) == [root.id, older.id, newer.id]
  end

  test "a thread whose workspace is GONE lands in the default group — never dropped" do
    {:ok, workspace} = Bootstrap.ensure()
    {:ok, thread} = Channel.open_thread(%{title: "orphan"})
    Server.Repo.query!("PRAGMA foreign_keys = OFF")
    Server.Repo.query!("UPDATE thread SET workspace_id = 999 WHERE id = ?", [thread.id])
    Server.Repo.query!("PRAGMA foreign_keys = ON")

    [%{workspace: %{id: default_id}, threads: threads}] = Board.sidebar()
    assert default_id == workspace.id
    assert Enum.any?(threads, &(&1.id == thread.id))
  end

  test "working and lead ride on the row; crew carries working flags" do
    {:ok, _workspace} = Bootstrap.ensure()
    # open_thread now assigns the workspace's builder (hronir) as lead automatically (the lead invariant).
    {:ok, thread} = Channel.open_thread(%{title: "busy thread"})
    :ok = Thinking.thinking(thread.id, "hronir-machine")

    [%{threads: threads, crew: crew}] = Board.sidebar()
    row = Enum.find(threads, &(&1.id == thread.id))
    assert row.working == true
    assert row.lead == "hronir-machine"

    hronir = Enum.find(crew, &(&1.name == "hronir"))
    assert hronir.working == true
    tertius = Enum.find(crew, &(&1.name == "tertius"))
    assert tertius.working == false
  end
end
