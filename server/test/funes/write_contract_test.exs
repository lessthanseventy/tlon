defmodule Server.WriteContractTest do
  # §4 re-verified on exqlite. The spec's numbers were node:sqlite; prove the
  # contract holds on the Elixir adapter rather than assuming it. WAL and
  # foreign_keys are readable by PRAGMA; busy_timeout is NOT — exqlite installs a
  # custom busy handler via a NIF (not `PRAGMA busy_timeout`), so the only honest
  # test is the behaviour the spec measured: bounded wait, then a retryable error.
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias Server.Repo

  test "WAL journal mode is in force" do
    assert %{rows: [["wal"]]} = Repo.query!("PRAGMA journal_mode")
  end

  test "foreign keys are enforced" do
    assert %{rows: [[1]]} = Repo.query!("PRAGMA foreign_keys")
  end

  test "we configure a bounded busy_timeout of 100ms" do
    assert Repo.config()[:busy_timeout] == 100
  end

  test "a held write lock makes another writer wait ~100ms, then fail retryably (not instant, not forever)" do
    path = Repo.config()[:database]
    {:ok, holder} = Sqlite3.open(path)
    {:ok, other} = Sqlite3.open(path)
    :ok = Sqlite3.set_busy_timeout(other, 100)

    :ok = Sqlite3.execute(holder, "BEGIN IMMEDIATE")

    {elapsed_us, result} =
      :timer.tc(fn -> Sqlite3.execute(other, "BEGIN IMMEDIATE") end)

    :ok = Sqlite3.execute(holder, "ROLLBACK")
    Sqlite3.close(holder)
    Sqlite3.close(other)

    # A retryable failure, not a partial write or a hang.
    assert match?({:error, _}, result),
           "expected the contended writer to be refused, got #{inspect(result)}"

    # Bounded: it waited (not the ~0ms of no timeout) but nowhere near the 2000ms
    # default or forever — the "fail fast" the spec chose over "never waits".
    assert elapsed_us >= 50_000,
           "failed too fast (#{div(elapsed_us, 1000)}ms) — busy_timeout not applied"

    assert elapsed_us <= 800_000,
           "waited too long (#{div(elapsed_us, 1000)}ms) — not bounded at ~100ms"
  end
end
