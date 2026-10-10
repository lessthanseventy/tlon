defmodule Server.IntakeTest do
  # What keeps the backlog moving with nobody at the keyboard: while fewer worklines are in flight
  # than the cap, the most urgent ticket nothing blocks goes to the manager — one per pass.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Intake
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Intake"})
    test = self()

    %{
      ws: ws,
      route: fn t ->
        send(test, {:routed, t.id})
        {:ok, %{routed_to: "tertius"}}
      end
    }
  end

  defp file(ws, title, pri \\ "med"), do: elem(Tickets.file(%{workspace_id: ws.id, title: title, priority: pri}), 1)

  test "routes the most urgent ticket nothing blocks", %{ws: ws, route: route} do
    _low = file(ws, "later", "low")
    high = file(ws, "now", "high")
    _med = file(ws, "soon")

    Intake.run(cap: 4, route: route)
    assert_received {:routed, id}
    assert id == high.id
    refute_received {:routed, _}
  end

  test "among equally urgent tickets, the one on top of the board goes first", %{ws: ws, route: route} do
    older = file(ws, "older")
    newer = file(ws, "newer")
    assert hd(Tickets.in_workspace(ws.id)).id == newer.id
    assert Intake.next(ws.id).id == newer.id

    :ok = Tickets.reorder(older, :up)
    assert hd(Tickets.in_workspace(ws.id)).id == older.id

    Intake.run(cap: 4, route: route)
    assert_received {:routed, id}
    assert id == older.id
  end

  test "a held ticket is never routed — the next one goes instead", %{ws: ws, route: route} do
    held = file(ws, "renderer first", "high")
    {:ok, _} = Tickets.update(held, %{labels: ["held"]})
    next = file(ws, "soon")

    Intake.run(cap: 4, route: route)
    assert_received {:routed, id}
    assert id == next.id
  end

  test "a blocked ticket waits for its blocker to be done", %{ws: ws, route: route} do
    blocker = file(ws, "first", "low")
    blocked = file(ws, "second", "high")
    {:ok, _} = Tickets.link(blocker.id, blocked.id, "blocks")

    Intake.run(cap: 4, route: route)
    assert_received {:routed, id}
    assert id == blocker.id
  end

  test "nothing moves while the worklines in flight are at the cap", %{ws: ws, route: route} do
    _t = file(ws, "waiting", "high")

    {:ok, _} =
      Server.Workline.open(%{title: "busy", slug: "busy-#{System.unique_integer([:positive])}", workspace_id: ws.id})

    Intake.run(cap: 1, route: route)
    refute_received {:routed, _}
  end

  test "a workline waiting on the operator does not hold a slot — work goes on while gates queue", %{
    ws: ws,
    route: route
  } do
    t = file(ws, "next", "high")

    {:ok, w} =
      Server.Workline.open(%{
        title: "parked",
        slug: "parked-#{System.unique_integer([:positive])}",
        workspace_id: ws.id
      })

    {:ok, _} = w |> Ecto.Changeset.change(awaiting: "andrew") |> Server.Repo.update()

    Intake.run(cap: 1, route: route)
    assert_received {:routed, id}
    assert id == t.id
  end

  test "but how many may wait at once has a ceiling", %{ws: ws, route: route} do
    _t = file(ws, "next", "high")

    for i <- 1..2 do
      {:ok, w} =
        Server.Workline.open(%{
          title: "parked #{i}",
          slug: "parked-#{i}-#{System.unique_integer([:positive])}",
          workspace_id: ws.id
        })

      {:ok, _} = w |> Ecto.Changeset.change(awaiting: "andrew") |> Server.Repo.update()
    end

    Intake.run(cap: 4, max_open: 2, route: route)
    refute_received {:routed, _}
  end

  describe "a routed ticket nobody starts" do
    defp routed(ws, title, minutes_ago) do
      t = file(ws, title)
      {:ok, t} = Tickets.update(t, %{status: "todo"})
      at = DateTime.utc_now() |> DateTime.add(-minutes_ago * 60, :second) |> DateTime.truncate(:second)
      Server.Repo.update_all(from(x in Server.Ticket, where: x.id == ^t.id), set: [updated_at: at])
      t
    end

    test "is started by intake itself with the lead once 30 minutes pass — it never holds a slot in silence", %{
      ws: ws,
      route: route
    } do
      {:ok, lead} = Server.Workspaces.seat(ws.id, %{name: "hronir-i", archetype: "builder"})
      stalled = routed(ws, "floor step 3", 31)

      Intake.run(cap: 4, route: route)

      assert %{status: "doing"} = Tickets.get(stalled.id)
      assert [{"promoted", tid}] = Tickets.threads_of(stalled.id)
      assert %{stage: "build", agent_id: agent} = thread = Server.Repo.get!(Server.Thread, tid)
      assert agent == lead.agent_id
      assert Enum.any?(Server.Channel.thread_messages(thread), &(&1.body =~ "not staffed in 30 minutes"))
    end

    test "is left alone when the manager held it — the label says it waits on something", %{ws: ws, route: route} do
      held = routed(ws, "mailbox", 31)
      {:ok, _} = Tickets.update(held, %{labels: ["whimsy", "held"]})

      Intake.run(cap: 4, route: route)

      assert %{status: "todo"} = Tickets.get(held.id)
      assert Tickets.threads_of(held.id) == []
    end

    test "is started even when an earlier workline on it closed unmerged — that tie is history", %{
      ws: ws,
      route: route
    } do
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir-j", archetype: "builder"})
      again = routed(ws, "tried once", 31)
      {:ok, old} = Server.Channel.open_thread(%{title: "first try", workspace_id: ws.id})
      {:ok, _} = Tickets.tie(again, old.id, "promoted")
      {:ok, _} = Server.Channel.close_thread(old)
      at = DateTime.utc_now() |> DateTime.add(-31 * 60, :second) |> DateTime.truncate(:second)
      Server.Repo.update_all(from(x in Server.Ticket, where: x.id == ^again.id), set: [status: "todo", updated_at: at])

      Intake.run(cap: 4, route: route)

      assert %{status: "doing"} = Tickets.get(again.id)
      assert length(Tickets.threads_of(again.id)) == 2
    end

    test "is left with the manager inside the 30 minutes", %{ws: ws, route: route} do
      fresh = routed(ws, "just routed", 5)
      Intake.run(cap: 4, route: route)
      assert %{status: "todo"} = Tickets.get(fresh.id)
      assert Tickets.threads_of(fresh.id) == []
    end
  end

  test "a todo ticket whose promoted thread closed unmerged holds no slot", %{ws: ws, route: route} do
    stuck = file(ws, "stuck", "low")
    {:ok, stuck} = Tickets.update(stuck, %{status: "todo"})
    thread = Server.Repo.insert!(Server.Thread.open_changeset(%{title: "gave up", workspace_id: ws.id}))
    {:ok, _} = thread |> Server.Thread.state_changeset("closed") |> Server.Repo.update()
    {:ok, _} = Tickets.tie(stuck, thread.id, "promoted")
    next = file(ws, "next", "high")

    Intake.run(cap: 1, route: route)
    assert_received {:routed, id}
    assert id == next.id
  end

  test "the intake is on the cron" do
    crontab =
      Enum.find_value(Application.get_env(:server, Oban)[:plugins], fn
        {Oban.Plugins.Cron, o} -> o[:crontab]
        _ -> nil
      end)

    assert Enum.any?(crontab, &match?({_, Server.Jobs.Intake}, &1))
  end
end
