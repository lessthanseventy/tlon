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
    test "carries the workspaces, their benches, open threads and unstarted tickets", %{ws: ws} do
      {:ok, seat} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      {:ok, t} = Channel.open_thread(%{title: "wire the office", workspace_id: ws.id})
      {:ok, tk} = Tickets.file(%{workspace_id: ws.id, title: "a ticket"})

      s = Office.status()

      assert %{id: ws.id, name: "Machine"} in s.workspaces
      assert Enum.any?(s.bench, &(&1.workspace_id == ws.id and &1.name == "hronir" and &1.agent_id == seat.agent_id))
      assert %{id: tid, title: "wire the office", workspace_id: wsid} = Enum.find(s.threads, &(&1.id == t.id))
      assert {tid, wsid} == {t.id, ws.id}
      assert [%{id: tkid, routed: false}] = s.tickets
      assert tkid == tk.id
      assert s.awaiting == 0
      assert Enum.any?(s.archetypes, &(&1.name == "builder" and &1.meta == false))
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
      windows("0\tt#{desk.id}\t#{desk.id}\t\t\thronir\t")

      status = Office.status()
      seat = fn t -> Enum.find(status.threads, &(&1.id == t.id)).seat end
      assert {seat.(desk), seat.(parked), seat.(idle), seat.(gone)} == {"desk", "parked", "idle", "idle"}
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
      assert is_binary(JSON.encode!(v))
    end
  end
end
