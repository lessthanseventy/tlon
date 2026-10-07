defmodule Server.TestDatabaseNameTest do
  use ExUnit.Case, async: true

  # config/test.exs computes the per-checkout test database from this same function
  # (loaded via config/support/test_database_name.exs) — this test pins the naming
  # rule so a checkout-path regex change can't silently collide two worktrees' dbs again.
  alias Server.TestDatabaseName

  test "a worktree checkout names tlon_test_<name>" do
    dir = "/home/andrew/projects/tlon/.worktrees/dbconnection-client-exited/server/config"
    assert TestDatabaseName.compute(dir, nil) == "tlon_test_dbconnection_client_exited"
  end

  test "non-word characters in the worktree name become underscores" do
    dir = "/home/andrew/projects/tlon/.worktrees/a.b c/server/config"
    assert TestDatabaseName.compute(dir, nil) == "tlon_test_a_b_c"
  end

  test "the main checkout (no .worktrees/ in its path) names tlon_test" do
    dir = "/home/andrew/projects/tlon/server/config"
    assert TestDatabaseName.compute(dir, nil) == "tlon_test"
  end

  test "TLON_TEST_DATABASE overrides the computed name, even inside a worktree" do
    dir = "/home/andrew/projects/tlon/.worktrees/dbconnection-client-exited/server/config"
    assert TestDatabaseName.compute(dir, "my_custom_db") == "my_custom_db"
  end
end
