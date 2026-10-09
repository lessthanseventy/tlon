defmodule Server.Bench.Roles.RunnerSeedTest do
  use ExUnit.Case, async: true

  alias Server.Bench.Roles.Runner

  @git ["-c", "user.name=t", "-c", "user.email=t@localhost"]

  defp git!(dir, args), do: {_, 0} = System.cmd("git", @git ++ args, cd: dir, stderr_to_stdout: true)

  setup do
    tmp = Path.join(System.tmp_dir!(), "bench-seed-test-#{System.unique_integer([:positive])}")
    root = Path.join(tmp, "root")
    File.mkdir_p!(Path.join(root, "server"))
    File.write!(Path.join(root, "server/a.txt"), "a")
    git!(root, ["init", "-q"])
    git!(root, ["add", "-A"])
    git!(root, ["commit", "-qm", "one"])
    File.write!(Path.join(root, "server/x.txt"), "x")
    File.mkdir_p!(Path.join(root, "server/lib"))
    File.mkdir_p!(Path.join(root, "server/test"))
    File.write!(Path.join(root, "server/lib/y.ex"), "y")
    File.write!(Path.join(root, "server/test/y_test.exs"), "t")
    git!(root, ["add", "-A"])
    git!(root, ["commit", "-qm", "two"])
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp, root: root, sha: String.trim(sha)}
  end

  test "seed_source leaves the commit's parent state, committed as a fresh fixture repo", c do
    work = Path.join(c.tmp, "work")
    File.mkdir_p!(work)
    Runner.seed_source(c.root, c.sha, work)

    assert File.read!(Path.join(work, "server/a.txt")) == "a"
    refute File.exists?(Path.join(work, "server/x.txt"))
    {log, 0} = System.cmd("git", ["log", "--format=%s"], cd: work)
    assert String.trim(log) == "fixture"
  end

  test "reference_patch is the commit's change minus its tests, which stay hidden", c do
    patch = Runner.reference_patch(c.root, c.sha)
    assert patch =~ "server/lib/y.ex"
    refute patch =~ "y_test"
    assert patch =~ "server/x.txt"
  end

  test "apply_reference puts the real solution into the workdir", c do
    work = Path.join(c.tmp, "work")
    File.mkdir_p!(work)
    Runner.seed_source(c.root, c.sha, work)
    :ok = Runner.apply_reference(c.root, c.sha, work)
    assert File.read!(Path.join(work, "server/lib/y.ex")) == "y"
  end
end
