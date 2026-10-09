defmodule Server.Bench.Roles.RunnerTest do
  use ExUnit.Case, async: true

  alias Server.Bench.Roles.Runner

  defp tmp! do
    dir = Path.join(System.tmp_dir!(), "bench-runner-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  describe "seed_snapshot/2" do
    test "extracts the server tree at a commit into a fresh repo with one commit" do
      work = tmp!()
      Runner.seed_snapshot("HEAD", work)

      assert File.regular?(Path.join(work, "server/mix.exs"))
      {log, 0} = System.cmd("git", ["log", "--format=%s"], cd: work)
      assert String.split(log, "\n", trim: true) == ["fixture"]
    end

    test "the build is a private copy of the live one, never a link into it" do
      work = tmp!()
      Runner.seed_snapshot("HEAD", work)

      build = Path.join(work, "server/_build")
      assert {:ok, %{type: :directory}} = File.lstat(build)
      refute File.exists?(Path.join(build, "test/lib/server"))
      assert {:ok, %{type: :symlink}} = File.lstat(Path.join(work, "server/deps"))
    end
  end

  describe "the check" do
    test "gets the task's private database name in its env" do
      work = tmp!()
      task = %{dir: work, grader: %{"kind" => "check", "cmd" => ~s(test "$TLON_TEST_DATABASE" = mine)}}

      assert %{passed: true} = Runner.check(task, work, [{"TLON_TEST_DATABASE", "mine"}])
      assert %{passed: false} = Runner.check(task, work, [{"TLON_TEST_DATABASE", "other"}])
    end

    test "a database name is unique per run and a safe identifier" do
      [{"TLON_TEST_DATABASE", a}] = Runner.task_env(%{id: "s2-intake-slot"})
      [{"TLON_TEST_DATABASE", b}] = Runner.task_env(%{id: "s2-intake-slot"})

      assert a != b
      assert a =~ ~r/^tlon_bench_s2_intake_slot_\d+$/
    end

    test "drop_database removes a database a lingering process is still connected to" do
      [{"TLON_TEST_DATABASE", db}] = env = Runner.task_env(%{id: "drop-me"})
      {_, 0} = System.cmd("createdb", [db])
      port = Port.open({:spawn_executable, System.find_executable("psql")}, [:binary, args: [db]])
      Process.sleep(500)

      Runner.drop_database(env)
      Port.close(port)

      {dbs, 0} = System.cmd("psql", ["-Atc", "select datname from pg_database", "postgres"])
      refute db in String.split(dbs, "\n", trim: true)
    end
  end
end
