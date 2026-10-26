defmodule Server.Smoke.FixturesTest do
  use ExUnit.Case, async: false

  alias Server.Smoke.Fixtures

  setup do
    Server.TestDB.clean!()
    for n <- Server.Rollout.pending(), do: Server.Rollout.dismiss(n.id)
    :ok
  end

  test "names/0 lists the catalog" do
    assert "tool_denied_need" in Fixtures.names()
  end

  test "tool_denied_need seeds an open thread the Needs list reports as tool_denied" do
    assert :ok = Fixtures.apply("tool_denied_need", "tlon_smoke_4100")
    assert [%{kind: "tool_denied", level: "blocking"}] = Server.Office.Needs.list()
  end

  test "ticket_tree seeds an initiative, its epic, a free child, a child in flight and a loose ticket" do
    assert "ticket_tree" in Fixtures.names()
    assert :ok = Fixtures.apply("ticket_tree", "tlon_smoke_4100")

    by_title = Map.new(Server.Tickets.in_workspace(Server.Bootstrap.default_workspace_id()), &{&1.title, &1})
    initiative = by_title["fixture: an initiative"]
    epic = by_title["fixture: an epic"]
    free = by_title["fixture: a free child"]
    in_flight = by_title["fixture: a child in flight"]

    assert %{kind: "initiative"} = initiative
    assert %{kind: "epic"} = epic
    assert %{kind: "ticket", status: "backlog"} = free
    assert %{kind: "ticket", status: "doing"} = in_flight
    assert %{kind: "ticket"} = by_title["fixture: a loose ticket"]

    assert Server.Tickets.epic_of(epic.id) == initiative.id
    assert Server.Tickets.epic_of(free.id) == epic.id
    assert Server.Tickets.epic_of(in_flight.id) == epic.id
    assert [{"promoted", _thread}] = Server.Tickets.threads_of(in_flight.id)
  end

  test "an unknown name raises" do
    assert_raise ArgumentError, ~r/unknown fixture "nope"/, fn -> Fixtures.apply("nope", "tlon_smoke_4100") end
  end

  test "any db that is not tlon_smoke_* is refused, seeding nothing" do
    for db <- ["tlon", "tlon_test", nil] do
      assert_raise ArgumentError, ~r/tlon_smoke_/, fn -> Fixtures.apply("tool_denied_need", db) end
    end

    assert [] = Server.Office.Needs.list()
  end
end
