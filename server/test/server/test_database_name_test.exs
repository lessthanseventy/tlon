defmodule Server.TestDatabaseNameTest do
  use ExUnit.Case, async: true

  # config/test.exs computes the per-checkout test database from this same function
  # (loaded via config/support/test_database_name.exs) — this test pins the naming
  # rule so a checkout-path change can't silently collide two worktrees' dbs again.
  alias Server.TestDatabaseName

  defp checkout(tmp_dir, name, git) do
    root = Path.join(tmp_dir, name)
    config = Path.join(root, "server/config")
    File.mkdir_p!(config)

    case git do
      :dir -> File.mkdir_p!(Path.join(root, ".git"))
      :file -> File.write!(Path.join(root, ".git"), "gitdir: /elsewhere/.git/worktrees/#{name}\n")
    end

    config
  end

  @tag :tmp_dir
  test "the main checkout (.git is a directory) names tlon_test", %{tmp_dir: tmp} do
    assert TestDatabaseName.compute(checkout(tmp, "tlon", :dir), nil) == "tlon_test"
  end

  @tag :tmp_dir
  test "a git worktree anywhere (.git is a file) names tlon_test_<name>_<hash>", %{tmp_dir: tmp} do
    name = TestDatabaseName.compute(checkout(tmp, "agent-a785e4e2", :file), nil)
    assert name =~ ~r/^tlon_test_agent_a785e4e2_[0-9a-f]{8}$/
  end

  @tag :tmp_dir
  test "two worktrees with the same name at different paths get different dbs", %{tmp_dir: tmp} do
    a = TestDatabaseName.compute(checkout(Path.join(tmp, "a"), "wt", :file), nil)
    b = TestDatabaseName.compute(checkout(Path.join(tmp, "b"), "wt", :file), nil)
    assert a != b
    assert a == TestDatabaseName.compute(Path.join(tmp, "a/wt/server/config"), nil)
  end

  @tag :tmp_dir
  test "a long worktree name stays inside Postgres's 63-byte identifier limit", %{tmp_dir: tmp} do
    name = TestDatabaseName.compute(checkout(tmp, String.duplicate("x", 100), :file), nil)
    assert byte_size(name) <= 63
  end

  test "a path in no git checkout names tlon_test" do
    assert TestDatabaseName.compute("/nonexistent/server/config", nil) == "tlon_test"
  end

  @tag :tmp_dir
  test "TLON_TEST_DATABASE overrides the computed name, even inside a worktree", %{tmp_dir: tmp} do
    assert TestDatabaseName.compute(checkout(tmp, "wt", :file), "my_custom_db") == "my_custom_db"
  end
end
