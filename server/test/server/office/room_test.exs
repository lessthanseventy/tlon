defmodule Server.Office.RoomChecksTest do
  # The rack's queues: the machine's checks queue as its lock files say it, and the merge queue.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Office.Room

  test "the checks queue: who holds the lock and who waits, a waiter whose process is gone not counted, waiters in ticket order" do
    dir = Path.join(System.tmp_dir!(), "checks-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "tlon-checks.wait"))
    on_exit(fn -> File.rm_rf!(dir) end)

    assert Room.checks(dir) == %{running: nil, waiting: []}

    File.write!(Path.join(dir, "tlon-checks.holder"), "mise run check:all (pid 999999998) in /gone since 21:00:00\n")
    assert Room.checks(dir).running == nil

    File.write!(Path.join(dir, "tlon-checks.holder"), "mise run check:all (pid 1) in /w since 21:49:17\n")
    me = System.pid()
    wait = Path.join(dir, "tlon-checks.wait")
    File.write!(Path.join(wait, "0000000002-#{me}"), "second (pid #{me}) in /v since 21:50:01\n")
    File.write!(Path.join(wait, "0000000001-#{me}"), "first (pid #{me}) in /v since 21:50:00\n")
    File.write!(Path.join(wait, "0000000003-999999999"), "gone\n")
    File.write!(Path.join(wait, "junk"), "not an entry\n")

    assert %{
             running: "mise run check:all (pid 1) in /w since 21:49:17",
             waiting: ["first (pid" <> _, "second (pid" <> _]
           } =
             Room.checks(dir)
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

  test "a reviewed PR is on the same line, named as the PR, on the thread its review was recorded on" do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    {:ok, a} = Server.Channel.open_thread(%{title: "approved workline"})
    {:ok, r} = Server.Channel.open_thread(%{title: "review chat-ux"})
    {:ok, _} = %{thread_id: a.id} |> Server.Jobs.Land.new() |> Oban.insert()
    {:ok, _} = %{"pr" => 7, "branch" => "chat-ux", "on_thread" => r.id} |> Server.Jobs.Land.new() |> Oban.insert()

    assert [%{title: "approved workline"}, %{title: "PR #7 chat-ux", thread_id: id, state: "queued"}] =
             Room.merge_queue()

    assert id == r.id
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

  test "activity: a handoff_opened row names the old lead as who", ctx do
    {:ok, _} =
      Dossier.record_event(%{
        thread_id: ctx.t.id,
        kind: "handoff_opened",
        detail: %{"from" => "sandra", "to" => "robert"}
      })

    assert [%{kind: "handoff_opened", who: "sandra", thread_id: tid}] = Room.activity(ctx.ws.id)
    assert tid == ctx.t.id
  end

  test "triage: an issue a ticket took names the ticket and where it stands", ctx do
    {:ok, issue} = Dossier.raise_issue(%{thread_id: ctx.t.id, summary: "a flake"})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: ctx.ws.id, title: "fix the flake"})
    {:ok, _} = Dossier.own_issue(issue, ticket, "tertius")

    assert [%{issue_id: id, ticket_id: tid, ticket_status: "backlog"}] = Room.triage(ctx.ws.id).blockers.shown
    assert {id, tid} == {issue.id, ticket.id}
  end

  test "triage: open issues, a command whose NEWEST check failed, threads nobody leads", ctx do
    {:ok, _} = Dossier.raise_issue(%{thread_id: ctx.t.id, summary: "blocked on review"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "mix test"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "mix credo"})
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 0, cmd: "mix credo"})
    # a stage's doc not written yet is work in progress, not a failure to triage
    {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 1, cmd: "workline artifact spec.md"})

    tr = Room.triage(ctx.ws.id)

    assert [%{text: "blocked on review", summary: "blocked on review", issue_id: issue_id} = blocker] =
             tr.blockers.shown

    assert blocker.thread_id == ctx.t.id
    assert Map.has_key?(blocker, :evidence) and Map.has_key?(blocker, :found_by) and blocker.created_at
    assert is_integer(issue_id)
    assert [%{text: "mix test", check_id: check_id, stage: stage, thread_id: tid} = failed] = tr.failed_checks.shown
    assert is_integer(check_id) and Map.has_key?(failed, :slug) and tid == ctx.t.id and stage == ctx.t.stage
    assert [%{thread_id: _}] = tr.unled.shown
    assert tr.count == length(tr.blockers.shown) + 1 + length(tr.unled.shown)
    assert Room.triage(ctx.other.id).count == 0
  end

  test "triage: every failed check thread is named, however many the shown list caps", ctx do
    for n <- 1..7 do
      {:ok, t} = Channel.open_thread(%{title: "red #{n}", workspace_id: ctx.ws.id})
      {:ok, _} = Dossier.record_check(%{thread_id: t.id, exit: 1, cmd: "mix test"})
    end

    tr = Room.triage(ctx.ws.id)

    assert length(tr.failed_checks.shown) == 5
    assert tr.failed_checks.more == 2
    assert length(tr.failed_thread_ids) == 7
    assert Enum.all?(tr.failed_checks.shown, &(&1.thread_id in tr.failed_thread_ids))
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

    test "an initiative is no loose ticket; each epic row names the initiative it sits under", %{ws: ws, mk: mk} do
      kids = mk.(%{title: "Kids", kind: "initiative"})
      toy = mk.(%{title: "Toy", kind: "epic", epic_id: kids.id})
      bare = mk.(%{title: "Bare", kind: "epic"})

      %{epics: rows, loose: []} = Room.board(ws.id)
      by = Map.new(rows, &{&1.id, &1})
      assert by[toy.id].initiative == %{id: kids.id, title: "Kids"}
      assert by[bare.id].initiative == nil
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
