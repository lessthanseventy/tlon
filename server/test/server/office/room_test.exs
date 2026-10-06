defmodule Server.Office.RoomTest do
  # `Server.Office.Room` — the reads behind the office's things you open: the in-tray, the beacon,
  # the rack, the bookshelf, the ticket board, the finder's history.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Office.Room
  alias Server.Tickets
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Machine"})
    {:ok, other} = Workspaces.register(%{name: "Elsewhere"})
    {:ok, t} = Channel.open_thread(%{title: "wire the tray", workspace_id: ws.id})
    {:ok, ws: ws, other: other, t: t}
  end

  test "activity: the workspace's messages, issues and checks, newest first; never another's", ctx do
    {:ok, far} = Channel.open_thread(%{title: "far", workspace_id: ctx.other.id})
    {:ok, _} = Channel.post(%{thread_id: far.id, author: "andrew", body: "not here"})
    {:ok, _} = Channel.post(%{thread_id: ctx.t.id, author: "andrew", body: "hello tray"})
    {:ok, _} = Dossier.raise_issue(%{thread_id: ctx.t.id, summary: "the build is red", found_by: "hronir"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "mix test"})

    feed = Room.activity(ctx.ws.id)

    assert feed |> Enum.map(& &1.kind) |> Enum.sort() == ["check_failed", "issue", "message"]
    assert Enum.any?(feed, &(&1.kind == "issue" and &1.who == "hronir" and &1.text == "the build is red"))
    refute Enum.any?(feed, &(&1.text == "not here"))
    assert is_binary(JSON.encode!(feed))
  end

  test "triage: open issues, a command whose NEWEST check failed, threads nobody leads", ctx do
    {:ok, _} = Dossier.raise_issue(%{thread_id: ctx.t.id, summary: "blocked on review"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "mix test"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "mix credo"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 0, cmd: "mix credo"})

    tr = Room.triage(ctx.ws.id)

    assert [%{text: "blocked on review"}] = tr.blockers.shown
    assert [%{text: "mix test"}] = tr.failed_checks.shown
    assert tr.count == length(tr.blockers.shown) + 1 + length(tr.unled.shown)
    assert Room.triage(ctx.other.id).count == 0
  end

  test "health: says ok or names its problems, and encodes" do
    h = Room.health()
    assert h.db
    assert h.state in ["ok", "warn"]
    assert h.state == "ok" or h.problems != []
    assert is_binary(JSON.encode!(h))
  end

  test "memory: pinned facts with their ids, habits awaiting review", ctx do
    {:ok, f} = Dossier.bank_fact(%{kind: "constraint", text: "presses Enter", provenance: "stated"})
    {:ok, h} = Dossier.propose_habit(%{text: "run the gate first", proposed_by: "hronir"})

    m = Room.memory(ctx.ws.id)

    assert %{id: f.id, text: "presses Enter"} in m.pinned
    assert Enum.any?(m.habits, &(&1.id == h.id and &1.by == "hronir"))
  end

  test "tickets: every status, with what blocks each", ctx do
    {:ok, a} = Tickets.file(%{workspace_id: ctx.ws.id, title: "a"})
    {:ok, b} = Tickets.file(%{workspace_id: ctx.ws.id, title: "b"})
    {:ok, _} = Tickets.update(b, %{status: "doing"})
    {:ok, _} = Tickets.link(a.id, b.id, "blocks")

    board = Room.tickets(ctx.ws.id)

    assert %{status: "doing", blocked_by: [a_id]} = Enum.find(board, &(&1.id == b.id))
    assert a_id == a.id
  end

  test "history: closed threads only", ctx do
    {:ok, _} = Channel.close_thread(ctx.t)
    assert [%{id: id, title: "wire the tray"}] = Room.history()
    assert id == ctx.t.id
  end
end
