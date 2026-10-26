defmodule Server.WakeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Wake

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)
    {:ok, ws} = Server.Workspaces.register(%{name: "Seated"})
    {:ok, thread} = Channel.open_thread(%{title: "a pane that never drains", workspace_id: ws.id})
    %{thread: thread}
  end

  # A seat whose pane is up: a live session on the thread and a window tagged with its name.
  defp live_seat!(thread, name) do
    {:ok, a} = Server.Staff.register_agent(%{name: name, mandate: "m", engine: "e"})
    {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: thread.id, pane_ref: "%1"})
    windows!("1\tt#{thread.id}\t#{thread.id}\t\t100\t#{name}\t0\t\t%1")
  end

  defp windows!(out), do: Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {out, 0} end)

  test "a wake its pane never took is reported and let go; a fresh one waits", %{thread: t} do
    live_seat!(t, "hronir")
    {:ok, old} = Wake.queue(t.id, "hronir", "ping")
    old_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(w in Wake, where: w.id == ^old.id), set: [inserted_at: old_at])
    {:ok, _fresh} = Wake.queue(t.id, "hronir", "pong")

    assert Wake.report_overdue() == 1
    assert Wake.take(t.id, "hronir") == ["pong"]
  end

  test "a wake whose pane is mid-turn (a long tool call) is not overdue; one past the stale-turn clock is",
       %{thread: t} do
    live_seat!(t, "nolan")
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

  test "a windowless live session beside a windowed superseded one is not a seat: nothing is paged",
       %{thread: t} do
    {:ok, a} = Server.Staff.register_agent(%{name: "vera", mandate: "m", engine: "e"})
    {:ok, old} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id, pane_ref: "%474"})
    Repo.update_all(from(s in Server.Session, where: s.id == ^old.id), set: [ended_at: DateTime.utc_now()])
    {:ok, _live} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
    windows!("1\tt#{t.id}\t#{t.id}\t\t100\tvera\t0\t\t%474")

    {:ok, w} = Wake.queue(t.id, "vera", "ping")
    at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(x in Wake, where: x.id == ^w.id), set: [inserted_at: at])

    assert Wake.report_overdue() == 0
  end

  describe "the sheriff's page" do
    setup do
      {:ok, ws} = Server.Workspaces.register(%{name: "Watched"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      {:ok, t} = Channel.open_thread(%{title: "a pane that never drains", workspace_id: ws.id})
      live_seat!(t, "pierre")
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

    test "a wake to a seat with no window never pages", %{ws: ws, t: t} do
      Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"no server running", 1} end)
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

      assert Wake.report_overdue() == 0
      assert pages(ws) == []
      assert Wake.take(t.id, "pierre") == []
    end

    test "a wake to a seat whose window has no session never pages", %{ws: ws, t: t} do
      Repo.update_all(Server.Session, set: [ended_at: DateTime.utc_now()])
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

      assert Wake.report_overdue() == 0
      assert pages(ws) == []
    end

    test "a wake to a seat with a session but no window never pages", %{ws: ws, t: t} do
      windows!("1\tscharlach\t\t\t100\tscharlach\t0")
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

      assert Wake.report_overdue() == 0
      assert pages(ws) == []
    end

    test "a wake to a seat that no longer holds the workline's stage never pages", %{ws: ws, t: t} do
      {:ok, emma} = Server.Staff.register_agent(%{name: "emma", mandate: "m", engine: "e"})
      {:ok, t} = Server.Staff.assign(t, emma)
      Repo.update_all(from(x in Server.Thread, where: x.id == ^t.id), set: [stage: "build"])
      {:ok, w} = Wake.queue(t.id, "pierre", "ping")
      age!(w)

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
