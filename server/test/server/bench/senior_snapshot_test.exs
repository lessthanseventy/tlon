defmodule Server.Bench.SeniorSnapshotTest do
  # Seeds every senior task at its parent commit and runs its hidden check there (`mise run bench:senior-verify`):
  # a check green before any work measures nothing; one the real solution cannot turn green is unwinnable.
  use ExUnit.Case, async: true

  alias Server.Bench.Roles
  alias Server.Bench.Roles.Runner

  @moduletag :bench_snapshot
  @moduletag timeout: 1_800_000

  @tasks Path.join(Server.Profiles.tlon_root(), "bench/roles/tasks")

  for t <- Roles.load(@tasks, "senior", "full") do
    @task Macro.escape(t)

    test "#{t.id}: red at its parent, green once the real solution's source changes are applied" do
      t = unquote(@task)
      work = Path.join(System.tmp_dir!(), "bench-senior-verify-#{t.id}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(work)
      env = Runner.task_env(t)
      on_exit(fn -> File.rm_rf!(work) && Runner.drop_database(env) end)

      Runner.seed_snapshot(t.snapshot["parent"], work)

      red = Runner.check(t, work, env)
      refute red.passed, "#{t.id}'s check passed at its parent, before any work"

      assert red.detail =~ ~r/Failed: \d+ tests?/,
             "#{t.id}'s check is red at its parent for a reason other than a failing test: #{red.detail}"

      root = Server.Profiles.tlon_root()
      {from, to} = {t.snapshot["parent"], t.snapshot["solution"]}

      {_, 0} =
        System.cmd("sh", ["-c", ~s(git -C "$0" diff "$1" "$2" -- server ':!server/test' | git apply -), root, from, to],
          cd: work
        )

      green = Runner.check(t, work, env)
      assert green.passed, "#{t.id}'s check fails with the real solution applied: #{green.detail}"
    end
  end
end
