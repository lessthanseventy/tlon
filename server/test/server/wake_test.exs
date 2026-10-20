defmodule Server.WakeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Wake

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "a pane that never drains"})
    %{thread: thread}
  end

  test "a wake its pane never took is reported and let go; a fresh one waits", %{thread: t} do
    {:ok, old} = Wake.queue(t.id, "hronir", "ping")
    old_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(w in Wake, where: w.id == ^old.id), set: [inserted_at: old_at])
    {:ok, _fresh} = Wake.queue(t.id, "hronir", "pong")

    assert Wake.report_overdue() == 1
    assert Wake.take(t.id, "hronir") == ["pong"]
  end

  test "a wake whose pane is mid-turn (a long tool call) is not overdue; one past the stale-turn clock is",
       %{thread: t} do
    {:ok, a} = Server.Staff.register_agent(%{name: "nolan", mandate: "m", engine: "e"})
    {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
    :ok = Server.Staff.mark_thinking(t.id, "nolan", DateTime.truncate(DateTime.utc_now(), :second))
    {:ok, old} = Wake.queue(t.id, "nolan", "ping")
    old_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(w in Wake, where: w.id == ^old.id), set: [inserted_at: old_at])

    assert Wake.report_overdue() == 0

    stale = DateTime.add(old_at, -Server.Presence.Thinking.stale_turn_seconds())
    :ok = Server.Staff.mark_thinking(t.id, "nolan", stale)
    assert Wake.report_overdue() == 1
    assert Wake.take(t.id, "nolan") == []
  end

  describe "the sheriff's page" do
    setup do
      {:ok, ws} = Server.Workspaces.register(%{name: "Watched"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      {:ok, t} = Channel.open_thread(%{title: "a pane that never drains", workspace_id: ws.id})
      %{ws: ws, t: t}
    end

    defp age!(wake, seconds \\ 600) do
      at = DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)
      Repo.update_all(from(w in Wake, where: w.id == ^wake.id), set: [inserted_at: at])
    end

    defp pages(ws) do
      Repo.all(
        from m in Server.Message,
          join: t in Server.Thread,
          on: t.id == m.thread_id,
          where: t.workspace_id == ^ws.id and t.title == ^Server.Sheriff.beat_title() and like(m.body, "🚨%"),
          order_by: m.id
      )
    end

    defp backdate_messages!(seconds) do
      at = DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)
      Repo.update_all(Server.Message, set: [created_at: at])
    end

    test "closing a thread lets go of its wakes", %{t: t} do
      {:ok, _} = Wake.queue(t.id, "pierre", "ping")
      {:ok, _} = Channel.close_thread(t)

      assert Wake.take(t.id, "pierre") == []
    end

    test "a wake on a closed thread is not reported", %{ws: ws, t: t} do
      {:ok, _} = Channel.close_thread(t)
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

      assert Wake.report_overdue() == 0
      assert pages(ws) == []
    end

    test "a seat that posted anywhere since the wake was queued took it", %{ws: ws, t: t} do
      {:ok, lobby} = Channel.open_thread(%{title: "the lobby", workspace_id: ws.id})
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)
      {:ok, _} = Channel.post(%{thread_id: lobby.id, author: "pierre", body: "answered here"})

      assert Wake.report_overdue() == 0
      assert pages(ws) == []
      assert Wake.take(t.id, "pierre") == []
    end

    test "a post from before the wake was queued does not count", %{ws: ws, t: t} do
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "pierre", body: "old news"})
      backdate_messages!(3600)
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

      assert Wake.report_overdue() == 1
      assert [_] = pages(ws)
    end

    test "one stuck seat is paged once per stall, and again after it drains", %{ws: ws, t: t} do
      {:ok, a} = Wake.queue(t.id, "pierre", "one")
      age!(a)
      assert Wake.report_overdue() == 1
      assert [_] = pages(ws)

      {:ok, b} = Wake.queue(t.id, "pierre", "two")
      age!(b)
      assert Wake.report_overdue() == 0
      assert [_] = pages(ws)

      backdate_messages!(3000)
      {:ok, _} = Channel.post(%{thread_id: t.id, author: "pierre", body: "drained"})

      Repo.update_all(from(m in Server.Message, where: m.author == "pierre"),
        set: [created_at: DateTime.add(DateTime.utc_now(), -2000)]
      )

      {:ok, d} = Wake.queue(t.id, "pierre", "three")
      age!(d)

      assert Wake.report_overdue() == 1
      assert [_, _] = pages(ws)
    end
  end
end
