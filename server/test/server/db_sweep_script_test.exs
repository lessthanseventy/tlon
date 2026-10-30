defmodule Server.DbSweepScriptTest do
  # scripts/db-sweep.sh: drops the `<prefix><digits>` databases nothing is connected to. These run
  # against the machine's Postgres, so each test gets a prefix of its own (the script takes it as an
  # argument): the live `tlon_eval_*` databases are never in reach of a test.
  use ExUnit.Case, async: false

  @script Path.expand("../../../scripts/db-sweep.sh", __DIR__)
  @host System.get_env("PGHOST", "/run/postgresql")

  setup do
    prefix = "tlon_sweeptest_#{System.unique_integer([:positive])}_"
    on_exit(fn -> for db <- dbs(prefix), do: psql("DROP DATABASE IF EXISTS \"#{db}\" WITH (FORCE)") end)
    %{prefix: prefix}
  end

  defp psql(sql), do: System.cmd("psql", ["-h", @host, "-d", "postgres", "-XAtq", "-c", sql], stderr_to_stdout: true)

  defp dbs(prefix) do
    {out, 0} = psql("select datname from pg_database where datname like '#{prefix}%' order by 1")
    String.split(out, "\n", trim: true)
  end

  defp sweep(args), do: System.cmd("bash", [@script | args], stderr_to_stdout: true)

  test "an idle <prefix><digits> database is dropped, and the count is printed", %{prefix: p} do
    {_, 0} = psql("CREATE DATABASE \"#{p}999999\"")

    assert {out, 0} = sweep([p])
    assert out =~ "dropped 1"
    assert dbs(p) == []
  end

  test "a database something is connected to is kept", %{prefix: p} do
    db = "#{p}999998"
    {_, 0} = psql("CREATE DATABASE \"#{db}\"")

    holder =
      Task.async(fn ->
        System.cmd("psql", ["-h", @host, "-d", db, "-XAtq", "-c", "select pg_sleep(60)"], stderr_to_stdout: true)
      end)

    wait_until(fn -> {"1\n", 0} == psql("select count(*) from pg_stat_activity where datname = '#{db}'") end)

    assert {out, 0} = sweep([p])
    assert out =~ "dropped 0"
    assert dbs(p) == [db]

    psql("select pg_terminate_backend(pid) from pg_stat_activity where datname = '#{db}'")
    Task.shutdown(holder, :brutal_kill)
  end

  test "a name without a numeric suffix is untouched", %{prefix: p} do
    for suffix <- ["x", "999999x", "x999999", "_"] do
      {_, 0} = psql("CREATE DATABASE \"#{p}#{suffix}\"")
    end

    assert {out, 0} = sweep([p])
    assert out =~ "dropped 0"
    assert length(dbs(p)) == 4
  end

  test "a prefix that could reach beyond tlon_eval-style names is refused", %{prefix: p} do
    {_, 0} = psql("CREATE DATABASE \"#{p}1\"")

    for bad <- ["tlon", "tlon_", "", "x_", "tlon_eval_%", "tlon_eval_.*", "a'b_"] do
      assert {out, code} = sweep([bad])
      assert code != 0, "prefix #{inspect(bad)} was accepted"
      assert out =~ "refused"
    end

    assert dbs(p) == ["#{p}1"]
  end

  test "no argument means tlon_eval_, and the task is wired in tasks/server.toml" do
    assert File.read!(@script) =~ ~s(prefix="${1-tlon_eval_}")
    toml = File.read!(Path.expand("../../../tasks/server.toml", __DIR__))
    assert toml =~ ~s(["server:db-sweep"])
    assert toml =~ "scripts/db-sweep.sh"
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(100) && wait_until(fun, tries - 1)
    end
  end
end
