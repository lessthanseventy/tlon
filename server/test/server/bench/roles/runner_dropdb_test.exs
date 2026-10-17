defmodule Server.Bench.Roles.RunnerDropdbTest do
  # empties PATH for the whole VM, so it cannot run beside async tests
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Server.Bench.Roles.Runner

  test "drop_database with no dropdb on PATH says so instead of raising" do
    path = System.get_env("PATH")
    empty = Path.join(System.tmp_dir!(), "no-dropdb-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    System.put_env("PATH", empty)

    on_exit(fn ->
      System.put_env("PATH", path)
      File.rm_rf!(empty)
    end)

    out = capture_io(fn -> assert :skipped = Runner.drop_database(Runner.task_env(%{id: "no-dropdb"})) end)
    assert out =~ "dropdb not found"
  end
end
