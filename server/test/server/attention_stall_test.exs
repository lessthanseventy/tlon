defmodule Server.Attention.StallTest do
  # A coworker mid-turn whose pane has not changed for the band is flagged on its thread as a
  # `stall` row, resolved when the pane moves. tmux rides the `:tmux_cmd` seam; the clock is `now:`.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Attention.Stall
  alias Server.Channel
  alias Server.Message
  alias Server.Presence.Thinking
  alias Server.Repo
  alias Server.Workspaces

  @t0 ~U[2026-09-30 12:00:00Z]

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, thread} = Channel.open_thread(%{title: "orient", scope: "machine", workspace_id: ws.id})
    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)
    on_exit(fn -> Thinking.idle(thread.id, "builder") end)
    %{ws: ws, thread: thread}
  end

  defp tmux(windows) do
    Application.put_env(:server, :tmux_cmd, fn "tmux", args, _opts ->
      cond do
        "list-windows" in args -> {windows, 0}
        "capture-pane" in args -> {Process.get(:screen, ""), 0}
        true -> {"", 0}
      end
    end)
  end

  defp leaf(thread_id), do: "1\tt#{thread_id}\t#{thread_id}\t\t123\n"
  defp at(minutes), do: DateTime.add(@t0, minutes * 60)

  defp stalls(thread_id),
    do: Repo.all(from m in Message, where: m.thread_id == ^thread_id and m.kind == "stall", order_by: m.id)

  test "thinking with a frozen pane past the band opens ONE delivered stall row; the pane moving resolves it",
       %{thread: t} do
    tmux(leaf(t.id))
    :ok = Thinking.thinking(t.id, "builder")
    Process.put(:screen, "running tests…")

    panes = Stall.tick(%{}, now: at(0))
    panes = Stall.tick(panes, now: at(4))
    assert stalls(t.id) == []

    panes = Stall.tick(panes, now: at(5))
    panes = Stall.tick(panes, now: at(6))

    assert [%Message{author: "tlon", resolved_at: nil, delivered_at: %DateTime{}} = s] = stalls(t.id)
    assert s.body =~ "⚠ stalled"
    assert s.payload["window"] == "t#{t.id}"

    Process.put(:screen, "running tests… 42 passed")
    _ = Stall.tick(panes, now: at(7))
    assert [%Message{resolution: "pane moved", resolved_at: %DateTime{}}] = stalls(t.id)
  end

  test "a frozen pane nobody is thinking in is idle, not stalled", %{thread: t} do
    tmux(leaf(t.id))
    Process.put(:screen, "❯ ")

    panes = Stall.tick(%{}, now: at(0))
    _ = Stall.tick(panes, now: at(30))
    assert stalls(t.id) == []
  end

  test "a pane waiting on a permission dialog is the prompt's to report, not a stall", %{ws: ws, thread: t} do
    tmux(leaf(t.id))
    :ok = Thinking.thinking(t.id, "builder")
    Process.put(:screen, File.read!("test/fixtures/panes/claude_permission_prompt.txt"))
    :ok = Server.Attention.tick(ws.id)

    panes = Stall.tick(%{}, now: at(0))
    _ = Stall.tick(panes, now: at(10))
    assert stalls(t.id) == []
  end

  test "a standing-thread window stalls only when ITS agent is the one thinking", %{ws: ws} do
    standing = Channel.machine_thread(ws.id)
    tmux("0\tlead\t\t\t1\n1\treviewer\t\t\t2\n")
    :ok = Thinking.thinking(standing.id, "lead")
    on_exit(fn -> Thinking.idle(standing.id, "lead") end)
    Process.put(:screen, "same")

    panes = Stall.tick(%{}, now: at(0))
    _ = Stall.tick(panes, now: at(10))
    assert [%Message{payload: %{"window" => "lead"}}] = stalls(standing.id)
  end

  test "a restarted poller (no pane memory) keeps an open stall open", %{thread: t} do
    tmux(leaf(t.id))
    :ok = Thinking.thinking(t.id, "builder")
    Process.put(:screen, "x")
    panes = Stall.tick(%{}, now: at(0))
    _ = Stall.tick(panes, now: at(5))

    _ = Stall.tick(%{}, now: at(6))
    assert [%Message{resolved_at: nil}] = stalls(t.id)
  end

  test "a window that is gone closes its stall", %{thread: t} do
    tmux(leaf(t.id))
    :ok = Thinking.thinking(t.id, "builder")
    Process.put(:screen, "x")
    panes = Stall.tick(%{}, now: at(0))
    panes = Stall.tick(panes, now: at(5))

    tmux("")
    _ = Stall.tick(panes, now: at(6))
    assert [%Message{resolution: "window closed"}] = stalls(t.id)
  end
end
