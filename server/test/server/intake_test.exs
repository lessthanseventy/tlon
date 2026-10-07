defmodule Server.IntakeTest do
  # What keeps the backlog moving with nobody at the keyboard: while fewer worklines are in flight
  # than the cap, the most urgent ticket nothing blocks goes to the manager — one per pass.
  use ExUnit.Case, async: false

  alias Server.Intake
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Intake"})
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

  test "the intake is on the cron" do
    crontab =
      Enum.find_value(Application.get_env(:server, Oban)[:plugins], fn
        {Oban.Plugins.Cron, o} -> o[:crontab]
        _ -> nil
      end)

    assert Enum.any?(crontab, &match?({_, Server.Jobs.Intake}, &1))
  end
end
