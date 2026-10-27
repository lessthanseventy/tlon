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

  test "a fixture string carries its params: name:key=value,key=value" do
    assert {"quota_refused_need", %{}} = Fixtures.parse("quota_refused_need")
    assert {"x", %{"provider" => "ollama-cloud", "n" => "2"}} = Fixtures.parse("x:provider=ollama-cloud,n=2")

    for bad <- ["", "X", "x:", "x:a", "x:a=", "x:a=b c", "x:a=b,,c=d", "x:A=b"] do
      assert_raise ArgumentError, ~r/not a fixture/, fn -> Fixtures.parse(bad) end
    end
  end

  test "an unknown param raises, seeding nothing" do
    assert_raise ArgumentError, ~r/unknown param/, fn ->
      Fixtures.apply("quota_refused_need:nope=1", "tlon_smoke_4100")
    end
  end

  test "quota_refused_need seeds a non-anthropic provider's 429 as a quota Need (provider= picks it)" do
    assert :ok = Fixtures.apply("quota_refused_need", "tlon_smoke_4100")

    assert [%{kind: "quota", title: "ollama-cloud is spent"}] =
             Enum.filter(Server.Office.Needs.list(), &(&1.kind == "quota"))
  end

  test "failed_job seeds a discarded job as one job_failed Need" do
    assert :ok = Fixtures.apply("failed_job", "tlon_smoke_4100")

    assert [%{kind: "job_failed", title: "Server.Jobs.KeepUp failed", text: "fixture: boom"}] =
             Server.Office.Needs.list()
  end

  test "health_need seeds a box-health Need (what= picks disk, mem or tmux)" do
    on_exit(fn ->
      Application.delete_env(:server, :health_reading)
      :persistent_term.erase({Server.Office.Needs, :health_since})
    end)

    assert :ok = Fixtures.apply("health_need", "tlon_smoke_4100")
    assert [%{kind: "health", title: "the box: disk"}] = Server.Office.Needs.list()
    assert :ok = Fixtures.apply("health_need:what=mem", "tlon_smoke_4100")
    assert [%{kind: "health", title: "the box: mem"}] = Server.Office.Needs.list()
  end

  describe "Uqbar's verdicts (they route only with uqbar_routing on, so the fixture turns it on in a scratch config)" do
    setup do
      prior = Application.get_env(:server, :operator_config_path)

      on_exit(fn ->
        if prior,
          do: Application.put_env(:server, :operator_config_path, prior),
          else: Application.delete_env(:server, :operator_config_path)
      end)
    end

    test "settled_need puts a job_failed Need in Uqbar's settled group" do
      assert :ok = Fixtures.apply("settled_need", "tlon_smoke_4100")
      assert [%{kind: "job_failed", route: "settled"}] = Server.Office.Needs.grouped().settled
      assert Server.Office.Needs.grouped().uqbar == []
    end

    test "passed_up_need reaches the clipboard carrying Uqbar's recommendation" do
      assert :ok = Fixtures.apply("passed_up_need", "tlon_smoke_4100")

      assert [%{kind: "job_failed", route: "pass_up", recommendation: "retry it"}] =
               Server.Office.Needs.grouped().clipboard
    end
  end

  test "interrupted_schedule_run seeds a script schedule whose last run was cut off with exit 143" do
    assert :ok = Fixtures.apply("interrupted_schedule_run", "tlon_smoke_4100")

    s =
      Enum.find(
        Server.Schedules.in_workspace(Server.Bootstrap.default_workspace_id()),
        &(&1.title == "fixture: a script cut off")
      )

    assert [%{status: "interrupted", exit: 143}] = Server.Schedules.runs(s.id)
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
