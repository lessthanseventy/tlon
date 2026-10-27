defmodule Server.OfficeTest do
  # `Server.Office` — the office's read models (the desktop rail, the office TUI): one snapshot of
  # every workspace, and a close look at one thread.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Office
  alias Server.Tickets
  alias Server.Workspaces

  # a fake tmux whose list-windows prints `out` (index, name, thread, opening, pid, agent, born)
  defp windows(out) do
    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      if "list-windows" in args, do: {out, 0}, else: {"", 0}
    end)

    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)
  end

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Machine"})
    {:ok, ws: ws}
  end

  describe "status/0" do
    test "an outside citizen's open session is on the roster, with its thread as the focus", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "a focus", workspace_id: ws.id})
      {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name("uqbar").id, thread_id: t.id})

      assert %{thread_id: tid, workspace_id: wsid, thinking: false} =
               Enum.find(Office.status().roster, &(&1.agent == "uqbar"))

      assert {tid, wsid} == {t.id, ws.id}
      refute Enum.any?(Office.status().bench, &(&1.name == "uqbar"))
    end

    test "the release the service runs rides the snapshot", %{ws: ws} do
      assert Office.status().release == nil
      {:ok, %{id: tid}} = Channel.open_thread(%{title: "root", workspace_id: ws.id, scope: "machine"})

      {:ok, _} =
        Channel.post(%{
          thread_id: tid,
          author: "tlon",
          kind: "notice",
          body: "release abc1234 is live",
          payload: %{"live" => "abc1234def"}
        })

      assert %{sha: "abc1234def", cut_at: %DateTime{}} = Office.status().release
    end

    test "the newest live notice wins, and a rollback is just a newer sha", %{ws: ws} do
      assert Office.status().release == nil
      {:ok, %{id: tid}} = Channel.open_thread(%{title: "root", workspace_id: ws.id, scope: "machine"})

      for sha <- ["abc1234def", "0f00bar"] do
        {:ok, _} =
          Channel.post(%{thread_id: tid, author: "tlon", kind: "notice", body: "live", payload: %{"live" => sha}})
      end

      assert Office.status().release.sha == "0f00bar"
    end

    test "carries the workspaces, their benches, open threads and unstarted tickets", %{ws: ws} do
      {:ok, seat} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      {:ok, t} = Channel.open_thread(%{title: "wire the office", workspace_id: ws.id})
      {:ok, tk} = Tickets.file(%{workspace_id: ws.id, title: "a ticket"})

      s = Office.status()

      assert %{id: ws.id, name: "Machine", shift: "day"} in s.workspaces
      assert Enum.any?(s.bench, &(&1.workspace_id == ws.id and &1.name == "hronir" and &1.agent_id == seat.agent_id))
      assert %{id: tid, title: "wire the office", workspace_id: wsid} = Enum.find(s.threads, &(&1.id == t.id))
      assert {tid, wsid} == {t.id, ws.id}
      assert [%{id: tkid, routed: false}] = s.tickets
      assert tkid == tk.id
      assert s.awaiting == 0
      assert Enum.any?(s.archetypes, &(&1.name == "builder" and &1.meta == false))
    end

    test "tickets carry their epic: an epic is a row with progress and its next child, children name it", %{ws: ws} do
      {:ok, epic} = Tickets.file(%{workspace_id: ws.id, title: "Toy", kind: "epic"})
      {:ok, one} = Tickets.file(%{workspace_id: ws.id, title: "sandbox mode", epic_id: epic.id})
      {:ok, done} = Tickets.file(%{workspace_id: ws.id, title: "shipped", epic_id: epic.id})
      {:ok, _} = Tickets.update(done, %{status: "done"})
      {:ok, loose} = Tickets.file(%{workspace_id: ws.id, title: "loose one"})

      ts = Office.status().tickets

      assert %{kind: "epic", done: 1, total: 2, next: %{id: nid, title: "sandbox mode"}} =
               Enum.find(ts, &(&1.id == epic.id))

      assert nid == one.id
      assert %{kind: "ticket", epic_id: eid} = Enum.find(ts, &(&1.id == one.id))
      assert eid == epic.id
      assert %{kind: "ticket", epic_id: nil} = Enum.find(ts, &(&1.id == loose.id))
      refute Enum.any?(ts, &(&1.id == done.id))
    end

    test "an epic's child on a thread stays on the tree, naming its thread; a loose started ticket does not", %{ws: ws} do
      {:ok, epic} = Tickets.file(%{workspace_id: ws.id, title: "Toy", kind: "epic"})
      {:ok, idle} = Tickets.file(%{workspace_id: ws.id, title: "not started", epic_id: epic.id})
      {:ok, child} = Tickets.file(%{workspace_id: ws.id, title: "in flight", epic_id: epic.id})
      {:ok, loose} = Tickets.file(%{workspace_id: ws.id, title: "loose and started"})
      {:ok, th} = Server.Channel.open_thread(%{title: "in flight", workspace_id: ws.id})
      {:ok, _} = Tickets.promote(child, th.id)
      {:ok, _} = Tickets.promote(loose, th.id)

      ts = Office.status().tickets

      assert %{status: "doing", thread_id: tid} = Enum.find(ts, &(&1.id == child.id))
      assert tid == th.id
      assert %{thread_id: nil} = idle_row = Enum.find(ts, &(&1.id == idle.id))
      refute idle_row.status == "doing"
      refute Enum.any?(ts, &(&1.id == loose.id))
    end

    test "carries today's celebrations (none when the calendar is off)" do
      assert Office.status().celebrations == []
    end

    test "a thread carries who is mid-turn on it — a declared thinking, not a warm session", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "busy", workspace_id: ws.id})
      :ok = Server.Presence.Thinking.thinking(t.id, "hronir")
      on_exit(fn -> Server.Presence.Thinking.idle(t.id, "hronir") end)
      assert %{thinking: ["hronir"]} = Enum.find(Office.status().threads, &(&1.id == t.id))
      :ok = Server.Presence.Thinking.idle(t.id, "hronir")
      assert %{thinking: []} = Enum.find(Office.status().threads, &(&1.id == t.id))
    end

    test "a seat mid-turn carries what it is doing", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "busy", workspace_id: ws.id})
      {:ok, a} = Server.Staff.register_agent(%{name: "hronir", mandate: "m", engine: "pi"})
      {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
      :ok = Server.Presence.Thinking.thinking(t.id, "hronir")
      :ok = Server.Presence.Thinking.doing(t.id, "hronir", "search")
      on_exit(fn -> Server.Presence.Thinking.idle(t.id, "hronir") end)

      assert %{thinking: true, doing: "search"} = Enum.find(Office.status().roster, &(&1.agent == "hronir"))

      :ok = Server.Presence.Thinking.idle(t.id, "hronir")
      assert %{thinking: false, doing: nil} = Enum.find(Office.status().roster, &(&1.agent == "hronir"))
    end

    test "a thread carries where its lead is — at a desk, parked for a seat, or idle", %{ws: ws} do
      for name <- ~w(hronir borges otto), do: {:ok, _} = Workspaces.seat(ws.id, %{name: name, archetype: "builder"})

      staffed = fn title, lead ->
        {:ok, t} = Channel.open_thread(%{title: title, workspace_id: ws.id})
        {:ok, _} = Channel.assign_lead(t.id, lead)
        t
      end

      for name <- ~w(dana), do: {:ok, _} = Workspaces.seat(ws.id, %{name: name, archetype: "builder"})
      desk = staffed.("at a desk", "hronir")
      {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name("hronir").id, thread_id: desk.id})
      parked = staffed.("parked", "borges")
      :ok = Server.Staffing.note_parked(parked.id)
      idle = staffed.("idle", "otto")
      # a warm session whose window is gone (the pane closed, the session never ended) is no desk
      gone = staffed.("window gone", "dana")
      {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name("dana").id, thread_id: gone.id})
      # a window with no session behind it is no desk either
      {:ok, _} = Workspaces.seat(ws.id, %{name: "ana", archetype: "builder"})
      bare = staffed.("window only", "ana")

      windows("0\tt#{desk.id}\t#{desk.id}\t\t\thronir\t\n1\tt#{bare.id}\t#{bare.id}\t\t\tana\t")

      status = Office.status()
      seat = fn t -> Enum.find(status.threads, &(&1.id == t.id)).seat end

      assert {seat.(desk), seat.(parked), seat.(idle), seat.(gone), seat.(bare)} ==
               {"desk", "parked", "idle", "idle", "idle"}

      assert %{warm: false} = Enum.find(status.roster, &(&1.agent == "dana"))
      assert %{warm: true} = Enum.find(status.roster, &(&1.agent == "hronir"))
    end

    test "a thread says whether it is a standing duty — the sheriff's beat, a schedule's — not work",
         %{ws: ws} do
      {:ok, beat} = Channel.open_thread(%{title: Server.Sheriff.beat_title(), workspace_id: ws.id})
      {:ok, work} = Channel.open_thread(%{title: "a fix", workspace_id: ws.id})

      duty = fn t -> Enum.find(Office.status().threads, &(&1.id == t.id)).duty end
      assert {duty.(beat), duty.(work)} == {true, false}
    end

    test "a thread says whether it is uqbar's study, so a surface never matches it by title", %{ws: ws} do
      {:ok, uqbar} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      {:ok, other} = Channel.open_thread(%{title: "a thread uqbar was handed", workspace_id: ws.id, agent_id: uqbar.id})
      {:ok, study} = Server.Outside.study(ws.id)

      study? = fn t -> Enum.find(Office.status().threads, &(&1.id == t.id)).study end
      assert {study?.(study), study?.(other)} == {true, false}
    end

    test "carries each workspace's triage count and the service's health", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "stuck", workspace_id: ws.id})
      {:ok, _} = Server.Dossier.raise_issue(%{thread_id: t.id, summary: "blocked"})
      s = Office.status()
      assert s.triage[ws.id] >= 1
      assert s.health.state in ["ok", "warn"]
    end

    test "is plain data: it encodes as JSON", %{ws: ws} do
      {:ok, _} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      assert is_binary(JSON.encode!(Office.status()))
    end

    test "status/0 carries a life summary only for type: home workspaces" do
      {:ok, home} = Workspaces.register(%{name: "office-life-#{System.unique_integer()}", type: "home"})
      {:ok, code} = Workspaces.register(%{name: "office-code-#{System.unique_integer()}", type: "code"})

      status = Office.status()

      assert Map.has_key?(status.life, home.id)
      assert status.life[home.id] |> Map.keys() |> Enum.sort() == [:due, :level, :xp]
      refute Map.has_key?(status.life, code.id)
    end

    test "a tmux that stops answering keeps the room's last windows for a minute or two, then the room goes quiet", %{
      ws: ws
    } do
      {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      {:ok, t} = Channel.open_thread(%{title: "at a desk", workspace_id: ws.id})
      {:ok, _} = Channel.assign_lead(t.id, "hronir")
      {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name("hronir").id, thread_id: t.id})
      warm = fn -> Enum.find(Office.status().roster, &(&1.agent == "hronir")).warm end

      windows("0\tt#{t.id}\t#{t.id}\t\t\thronir\t")
      assert warm.()

      Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"no server running on /tmp/x", 1} end)
      assert warm.()

      key = {Server.Office, :windows, ws.id}
      {tabs, _at} = :persistent_term.get(key)
      :persistent_term.put(key, {tabs, System.monotonic_time(:second) - 600})
      refute warm.()
    end

    test "every roster row carries one status: working, waiting, idle, cold or off", %{ws: ws} do
      for name <- ~w(hronir borges dana otto),
          do: {:ok, _} = Workspaces.seat(ws.id, %{name: name, archetype: "builder"})

      {:ok, _} = Workspaces.seat(ws.id, %{name: "nolan", archetype: "builder", crew: "night"})

      on = fn name, title ->
        {:ok, t} = Channel.open_thread(%{title: title, workspace_id: ws.id})
        {:ok, _} = Channel.assign_lead(t.id, name)
        {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name(name).id, thread_id: t.id})
        t
      end

      busy = on.("hronir", "busy")
      asked = on.("borges", "asked")
      _cold = on.("dana", "cold")
      idle = on.("otto", "idle")
      resting = on.("nolan", "resting")
      :ok = Server.Presence.Thinking.thinking(busy.id, "hronir")
      on_exit(fn -> Server.Presence.Thinking.idle(busy.id, "hronir") end)

      {:ok, _} =
        Channel.post(%{
          thread_id: asked.id,
          author: "tlon",
          kind: "prompt",
          body: "waiting",
          payload: %{"window" => "t#{asked.id}", "summary" => "Proceed?", "options" => []}
        })

      windows(
        Enum.map_join(
          [{busy, "hronir"}, {asked, "borges"}, {idle, "otto"}, {resting, "nolan"}],
          fn {t, name} -> "0\tt#{t.id}\t#{t.id}\t\t\t#{name}\t\n" end
        )
      )

      roster = Office.status().roster
      status = fn name -> Enum.find(roster, &(&1.agent == name)).status end

      assert {status.("hronir"), status.("borges"), status.("otto"), status.("dana"), status.("nolan")} ==
               {:working, :waiting, :idle, :cold, :off}
    end
  end

  describe "aside_spec/3" do
    test "the command that asks a coworker one thing, for the caller to run", %{ws: ws} do
      {:ok, c} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      assert {:ok, %{argv: [_ | _] = argv}} = Office.aside_spec(ws.id, c.agent_id, "what is in main?")
      assert Enum.any?(argv, &String.contains?(&1, "what is in main?"))
      assert {:error, :not_on_bench} = Office.aside_spec(ws.id, 999_999, "x")
    end
  end

  describe "thread_view/1" do
    test "the thread's last messages, oldest first, and no pane when nothing runs it", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      {:ok, _} = Server.Attention.respond(t.id, "andrew", "first")
      {:ok, _} = Server.Attention.respond(t.id, "andrew", "second")

      v = Office.thread_view(t)

      assert v.messages |> Enum.map(& &1.body) |> Enum.take(-2) == ["first", "second"]
      assert v.peek == nil and v.window == nil
      assert v.activity == []
      assert is_binary(JSON.encode!(v))
    end

    test "each message carries the one it replies to", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      {:ok, q} = Channel.post(%{thread_id: t.id, author: "andrew", body: "q?"})
      {:ok, r} = Channel.post(%{thread_id: t.id, author: "ada", body: "a", reply_to: q.id})

      assert %{reply_to: nil} = Enum.find(Office.thread_view(t).messages, &(&1.id == q.id))
      assert %{reply_to: rid} = Enum.find(Office.thread_view(t).messages, &(&1.id == r.id))
      assert rid == q.id
    end

    test "what its coworkers have been doing, newest last", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "t", workspace_id: ws.id})
      Server.Presence.Thinking.record(t.id, "hronir", "edit", "Edit · office/kit/crew.ts")
      Server.Presence.Thinking.record(t.id, "hronir", "test", "Bash · mise run check")

      assert [%{kind: "edit", agent: "hronir"}, %{kind: "test", summary: "Bash · mise run check"}] =
               Office.thread_view(t).activity

      assert JSON.encode!(Office.thread_view(t)) =~ ~s("activity":[{)
    end
  end

  test "the snapshot says each workspace's tickets opened and closed this week, for the board's trend" do
    {:ok, ws} = Workspaces.register(%{name: "Trend"})
    {:ok, a} = Tickets.file(%{workspace_id: ws.id, title: "one"})
    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "two"})
    {:ok, _} = Tickets.update(a, %{status: "done"})

    assert %{opened: 2, closed: 1} = Office.status().ticket_week[ws.id]
  end

  test "the snapshot carries the server's open-ticket counts: per group row, per workspace and for the orphans" do
    {:ok, ws} = Workspaces.register(%{name: "Counts"})
    {:ok, ini} = Tickets.file(%{workspace_id: ws.id, title: "I", kind: "initiative"})
    {:ok, epic} = Tickets.file(%{workspace_id: ws.id, title: "E", kind: "epic", epic_id: ini.id})
    {:ok, a} = Tickets.file(%{workspace_id: ws.id, title: "a", epic_id: epic.id})
    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "b", epic_id: epic.id})
    {:ok, _} = Tickets.file(%{workspace_id: ws.id, title: "orphan"})
    {:ok, _} = Tickets.update(a, %{status: "done"})

    status = Office.status()
    rows = Map.new(status.tickets, &{&1.id, &1})
    assert %{open: 1} = rows[epic.id]
    assert %{open: 1} = rows[ini.id]
    assert %{total: 2, loose: 1} = status.ticket_open[ws.id]
  end
end
