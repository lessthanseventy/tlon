defmodule Server.ThreadPauseTest do
  # Pause one thread, not the whole office (#404): its lead is told to finish the turn, nothing but
  # the operator's own posts wakes it, it owes no nudge or stalled Need, and resume delivers what was
  # held and wakes the lead. Every other thread goes on as normal.
  use ExUnit.Case, async: false

  alias Server.Channel

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
    {:ok, _} = Server.Staff.start_session(%{thread_id: busy.id, agent_id: emma.id, pane_ref: "%9"})
    {:ok, quiet} = Channel.open_thread(%{title: "nobody here", workspace_id: ws.id})
    %{ws: ws, lobby: lobby, busy: busy, quiet: quiet}
  end

  test "a thread is born unpaused", %{busy: busy} do
    assert Server.Repo.get(Server.Thread, busy.id).paused_at == nil
  end
end
