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
