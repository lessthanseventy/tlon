defmodule Server.Office.RoomChecksTest do
  # The rack's queues: the machine's checks queue as its lock files say it, and the merge queue.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Office.Room

  test "the checks queue: who holds the lock and who waits, a waiter whose process is gone not counted" do
    dir = Path.join(System.tmp_dir!(), "checks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "tlon-checks.wait"))
    on_exit(fn -> File.rm_rf!(dir) end)

    assert Room.checks(dir) == %{running: nil, waiting: []}

    File.write!(Path.join(dir, "tlon-checks.holder"), "mise run check:all (pid 999999998) in /gone since 21:00:00\n")
    assert Room.checks(dir).running == nil

    File.write!(Path.join(dir, "tlon-checks.holder"), "mise run check:all (pid 1) in /w since 21:49:17\n")
    me = System.pid()
    File.write!(Path.join([dir, "tlon-checks.wait", me]), "mise run check:all (pid #{me}) in /v since 21:50:00\n")
    File.write!(Path.join([dir, "tlon-checks.wait", "999999999"]), "gone\n")

    assert %{running: "mise run check:all (pid 1) in /w since 21:49:17", waiting: [waiter]} = Room.checks(dir)
    assert waiter =~ "in /v"
  end

  test "the merge queue: the landing one first, then the queued, by thread" do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, a} = Server.Channel.open_thread(%{title: "first approved"})
    {:ok, b} = Server.Channel.open_thread(%{title: "second approved"})
    {:ok, _} = %{thread_id: a.id} |> Server.Jobs.Land.new() |> Oban.insert()
    {:ok, jb} = %{thread_id: b.id} |> Server.Jobs.Land.new() |> Oban.insert()
    Server.Repo.update_all(from(j in Oban.Job, where: j.id == ^jb.id), set: [state: "executing"])

    assert [%{title: "second approved", state: "landing"}, %{title: "first approved", state: "queued"}] =
             Room.merge_queue()
  end
end

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
    # a stage's doc not written yet is work in progress, not a failure to triage
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "workline artifact spec.md"})

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

  describe "board: epics with progress" do
    setup ctx do
      mk = fn attrs -> elem(Tickets.file(Map.merge(%{workspace_id: ctx.ws.id}, attrs)), 1) end
      %{mk: mk}
    end

    test "groups children under their epic with done/total, and the rest as loose", %{ws: ws, mk: mk} do
      toy = mk.(%{title: "Toy", kind: "epic", priority: "high"})
      a = mk.(%{title: "a", epic_id: toy.id, sort: 1})
      b = mk.(%{title: "b", epic_id: toy.id, sort: 2})
      loose = mk.(%{title: "loose"})
      {:ok, _} = Tickets.update(a, %{status: "done"})

      %{epics: [row], loose: [l]} = Room.board(ws.id)
      assert %{id: toy_id, title: "Toy", done: 1, total: 2, priority: "high", status: "doing"} = row
      assert toy_id == toy.id
      assert row.children |> Enum.map(& &1.id) |> Enum.sort() == [a.id, b.id]
      assert l.id == loose.id
    end

    test "next is the lowest-sort free child: skips done, blocked and held", %{ws: ws, mk: mk} do
      e = mk.(%{title: "E", kind: "epic"})
      done = mk.(%{title: "done", epic_id: e.id, sort: 1})
      blocked = mk.(%{title: "blocked", epic_id: e.id, sort: 2})
      _held = mk.(%{title: "held", epic_id: e.id, sort: 3, labels: ["held"]})
      free = mk.(%{title: "free", epic_id: e.id, sort: 4})
      blocker = mk.(%{title: "blocker"})
      {:ok, _} = Tickets.update(done, %{status: "done"})
      {:ok, _} = Tickets.link(blocker.id, blocked.id, "blocks")

      %{epics: [row]} = Room.board(ws.id)
      assert row.next == %{id: free.id, title: "free"}
    end

    test "an epic with nothing free has next nil; a child's effective priority is its epic's when higher",
         %{ws: ws, mk: mk} do
      e = mk.(%{title: "E", kind: "epic", priority: "high"})
      c = mk.(%{title: "c", epic_id: e.id, priority: "low"})
      {:ok, _} = Tickets.update(c, %{status: "done"})

      %{epics: [row]} = Room.board(ws.id)
      assert row.next == nil
      assert [%{effective_priority: "high"}] = row.children
    end

    test "epics order by urgency, then board order; no epics is just loose", %{ws: ws, mk: mk} do
      lo = mk.(%{title: "lo", kind: "epic", priority: "low"})
      hi = mk.(%{title: "hi", kind: "epic", priority: "high"})
      assert [hi.id, lo.id] == Enum.map(Room.board(ws.id).epics, & &1.id)
      assert %{epics: [], loose: []} = Room.board(elem(Workspaces.register(%{name: "Empty"}), 1).id)
    end
  end
end
