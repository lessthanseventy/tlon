defmodule Server.ThreadPauseTest do
  # Pause one thread, not the whole office (#404): its lead is told to finish the turn, nothing but
  # the operator's own posts wakes it, it owes no nudge or stalled Need, and resume delivers what was
  # held and wakes the lead. Every other thread goes on as normal.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Message
  alias Server.Pause
  alias Server.Switchboard

  setup do
    Server.TestDB.clean!()
    path = Path.join(System.tmp_dir!(), "tpause-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, ws} = Server.Workspaces.register(%{name: "Office"})
    {:ok, lobby} = Channel.open_thread(%{title: "lobby", workspace_id: ws.id, scope: "machine"})
    {:ok, busy} = Channel.open_thread(%{title: "the small joys", workspace_id: ws.id})
    {:ok, emma} = Server.Staff.register_agent(%{name: "emma", mandate: "builder", engine: "local"})
    {:ok, busy} = Server.Staff.assign(busy, emma)
    {:ok, _} = Server.Staff.start_session(%{thread_id: busy.id, agent_id: emma.id, pane_ref: "%9"})
    {:ok, quiet} = Channel.open_thread(%{title: "nobody here", workspace_id: ws.id})
    %{ws: ws, lobby: lobby, busy: busy, quiet: quiet}
  end

  defp bodies(thread), do: thread |> Channel.thread_messages() |> Enum.map(& &1.body)

  defp tlon_chats(thread),
    do: thread |> Channel.thread_messages() |> Enum.filter(&(&1.author == "tlon" and &1.kind == "chat"))

  defp paused_at(thread), do: Server.Repo.get(Server.Thread, thread.id).paused_at

  test "a thread is born unpaused", %{busy: busy} do
    assert paused_at(busy) == nil
  end

  test "pause marks one thread and tells its lead once, as a notice; the lobby and other threads hear nothing",
       %{lobby: lobby, busy: busy, quiet: quiet} do
    assert {:ok, %Server.Thread{paused_at: %DateTime{}}} = Pause.pause_thread(busy.id)
    assert Pause.thread_paused?(busy.id)
    refute Pause.thread_paused?(quiet.id)

    assert [%Message{kind: "notice", body: "✎ paused — finish this turn" <> rest}] =
             busy |> Channel.thread_messages() |> Enum.filter(&(&1.author == "tlon"))

    assert rest =~ "commit"
    assert bodies(lobby) == []
    assert bodies(quiet) == []

    assert {:ok, %Server.Thread{paused_at: %DateTime{}}} = Pause.pause_thread(busy.id)
    assert length(Enum.filter(bodies(busy), &(&1 =~ "paused"))) == 1
  end

  test "resume clears the mark and wakes the lead; resuming an unpaused thread says nothing", %{busy: busy} do
    {:ok, _} = Pause.pause_thread(busy.id)
    assert {:ok, %Server.Thread{paused_at: nil}} = Pause.resume_thread(busy.id)
    refute Pause.thread_paused?(busy.id)
    assert [%Message{body: "@emma ▶ back to work" <> _}] = tlon_chats(busy)

    assert {:ok, %Server.Thread{paused_at: nil}} = Pause.resume_thread(busy.id)
    assert length(tlon_chats(busy)) == 1
  end

  test "a missing thread is not found; a closed one is not open", %{quiet: quiet} do
    assert {:error, :not_found} = Pause.pause_thread(999_999)
    assert {:error, :not_found} = Pause.resume_thread(999_999)
    Server.Repo.update_all(from(t in Server.Thread, where: t.id == ^quiet.id), set: [state: "closed"])
    assert {:error, :not_open} = Pause.pause_thread(quiet.id)
    assert {:error, :not_open} = Pause.resume_thread(quiet.id)
  end

  test "office pencils down does not tell a paused thread again, and back to work neither wakes nor resumes it",
       %{busy: busy} do
    {:ok, _} = Pause.pause_thread(busy.id)
    {:ok, :pencils_down} = Pause.pencils_down()
    assert length(Enum.filter(bodies(busy), &(&1 =~ "finish this turn"))) == 1

    {:ok, :working} = Pause.back_to_work()
    assert tlon_chats(busy) == []
    assert Pause.thread_paused?(busy.id)
  end

  describe "delivery" do
    setup do
      Application.put_env(:server, :arbiter, Server.Arbiter.Test)
      Application.put_env(:server, :test_pid, self())

      on_exit(fn ->
        Application.delete_env(:server, :arbiter)
        Application.delete_env(:server, :test_pid)
      end)
    end

    test "a paused thread holds every wake but the operator's; another thread's lead is woken; resume delivers what was held",
         %{ws: ws, busy: busy} do
      {:ok, daneri} = Server.Staff.register_agent(%{name: "daneri", mandate: "builder", engine: "local"})
      {:ok, other} = Channel.open_thread(%{title: "next door", workspace_id: ws.id})
      {:ok, other} = Server.Staff.assign(other, daneri)
      {:ok, _} = Server.Staff.start_session(%{thread_id: other.id, agent_id: daneri.id, pane_ref: "%2"})

      {:ok, _} = Pause.pause_thread(busy.id)
      {:ok, held} = Channel.post(%{thread_id: busy.id, author: "daneri", body: "emma, one more thing"})
      assert {:pending, _} = Switchboard.deliver(held)
      refute_received {:woke, "%9", _}

      {:ok, m} = Channel.post(%{thread_id: other.id, author: "emma", body: "daneri, yours"})
      assert {:delivered, _} = Switchboard.deliver(m)
      assert_received {:woke, "%2", _}

      {:ok, op} = Channel.post(%{thread_id: busy.id, author: Server.OperatorConfig.operator(), body: "emma, status?"})
      assert {:delivered, _} = Switchboard.deliver(op)
      assert_received {:woke, "%9", _}

      {:ok, _} = Pause.resume_thread(busy.id)
      assert %Message{delivered_at: %DateTime{}} = Server.Repo.get(Message, held.id)
      assert_received {:woke, "%9", _}
    end
  end
end
