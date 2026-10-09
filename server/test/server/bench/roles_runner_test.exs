defmodule Server.Bench.Roles.RunnerTest do
  use ExUnit.Case, async: true

  alias Server.Bench.Roles
  alias Server.Bench.Roles.Runner

  test "a task's database is unique per run and a safe identifier" do
    [{"TLON_TEST_DATABASE", a}] = Runner.task_env(%{id: "s2-intake-closed-slot"})
    [{"TLON_TEST_DATABASE", b}] = Runner.task_env(%{id: "s2-intake-closed-slot"})

    assert a != b
    assert a =~ ~r/^tlon_bench_s2_intake_closed_slot_\d+$/
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

  test "a sourced task gets half an hour, a plain builder fifteen minutes" do
    assert Runner.timeout_s(%{set: "senior", source: %{"commit" => "x"}}) == 1800
    assert Runner.timeout_s(%{set: "builder", source: nil}) == 900
  end

  test "the seeded build never carries the app's own beams, which would look newer than the snapshot" do
    tmp = Path.join(System.tmp_dir!(), "bench-build-test-#{System.unique_integer([:positive])}")
    root = Path.join(tmp, "root")
    work = Path.join(tmp, "work")
    File.mkdir_p!(Path.join(root, "server/_build/test/lib/server/ebin"))
    File.mkdir_p!(Path.join(root, "server/_build/test/lib/ecto/ebin"))
    File.mkdir_p!(Path.join(root, "server/deps"))
    File.mkdir_p!(work)
    File.write!(Path.join(root, "server/mix.exs"), "")
    File.write!(Path.join(root, "server/_build/test/lib/server/ebin/a.beam"), "")
    on_exit(fn -> File.rm_rf!(tmp) end)
    git = &System.cmd("git", ["-c", "user.name=t", "-c", "user.email=t@l" | &1], cd: root)
    git.(["init", "-q"])
    git.(["add", "mix.exs"])
    git.(["add", "-f", "server/mix.exs"])
    git.(["commit", "-qm", "one"])
    git.(["commit", "-qm", "two", "--allow-empty"])
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

    Runner.seed_source(root, String.trim(sha), work)

    assert File.dir?(Path.join(work, "server/_build/test/lib/ecto"))
    refute File.exists?(Path.join(work, "server/_build/test/lib/server"))
  end

  test "a Claude Code run killed by the timeout still reports the usage it streamed" do
    lines = [
      ~s({"type":"system","subtype":"init"}),
      ~s({"type":"assistant","message":{"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":7}}}),
      ~s({"type":"assistant","message":{"usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":50,"cache_creation_input_tokens":0}}})
    ]

    {_reply, u} = Roles.parse_output(:claude_code, Enum.join(lines, "\n"))
    assert %{input: 12, output: 8, cache_read: 150, cache_write: 7, turns: 2} = u
  end
end
