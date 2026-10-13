defmodule Server.OutsideTest do
  # Uqbar design §6: the operator's own Claude Code session is a citizen — its posts signed as itself,
  # never as the operator — but not a seat: no desk, no staffing, no intake. And the door it posts
  # through can't be used to speak as a coworker on a bench.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Outside

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "the lobby"})
    %{thread: thread}
  end

  test "posts signed by the outside citizen, not the operator", %{thread: thread} do
    {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
    assert {:ok, %{author: "uqbar"}} = Outside.post(thread.id, "uqbar", "a margin note")
    assert %{author: "uqbar", body: "a margin note"} = List.last(Channel.thread_messages(thread))
  end

  test "a notice is an FYI: it wakes nobody, not even a live lead it names", %{thread: thread} do
    Application.put_env(:server, :arbiter, Server.Arbiter.Test)
    Application.put_env(:server, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)

    {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
    {:ok, yu} = Server.Staff.register_agent(%{name: "yu", mandate: "lead", engine: "fresh"})
    {:ok, _} = Server.Staff.assign(thread, yu)
    {:ok, _} = Server.Staff.start_session(%{agent_id: yu.id, thread_id: thread.id, pane_ref: "wYu"})

    assert {:ok, m} = Outside.post(thread.id, "uqbar", "@yu your smoke is down, nothing to do", notice: true)
    assert %{kind: "notice", author: "uqbar"} = m
    Server.Switchboard.deliver(m)
    Server.Switchboard.drain()
    refute_received {:woke, _, _}
    assert %DateTime{} = Server.Repo.get!(Server.Message, m.id).delivered_at
  end

  test "refuses a name that is a seated coworker, or no agent at all", %{thread: thread} do
    {:ok, ws} = Server.Workspaces.create(%{name: "Bench"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "tertius-o", archetype: "surveyor"})

    assert {:error, :seated} = Outside.post(thread.id, "tertius-o", "speaking for tertius")
    assert {:error, :no_such_citizen} = Outside.post(thread.id, "nobody", "hello")
    assert Channel.thread_messages(thread) == []
  end

  describe "uqbar in the app: a citizen with a window of its own" do
    test "names/0 lists the outside citizens: registered as outside, seated nowhere" do
      {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      {:ok, ws} = Server.Workspaces.register(%{name: "Bench"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      {:ok, _} = Server.Staff.register_agent(%{name: "by-hand", mandate: "m", engine: "claude-code"})

      assert Outside.names() == ["uqbar"]
    end

    test "study/1 is uqbar's own thread on a workspace, led by it: one, opened once, reopened fresh if closed" do
      {:ok, uqbar} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      {:ok, ws} = Server.Workspaces.register(%{name: "Home"})

      assert {:ok, %{agent_id: lead, workspace_id: wsid, state: "open"} = study} = Outside.study(ws.id)
      assert lead == uqbar.id and wsid == ws.id
      assert {:ok, %{id: same}} = Outside.study(ws.id)
      assert same == study.id

      {:ok, _} = Channel.close_thread(study)
      assert {:ok, %{id: fresh, state: "open"}} = Outside.study(ws.id)
      assert fresh != study.id
    end
  end
end
