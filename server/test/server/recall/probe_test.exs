defmodule Server.Recall.ProbeTest do
  use ExUnit.Case, async: true

  alias Server.Recall.Probe

  setup do
    repo = Path.join(System.tmp_dir!(), "probe-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(repo, "server/lib"))
    File.mkdir_p!(Path.join(repo, "tasks"))
    File.write!(Path.join(repo, "server/lib/a.ex"), "defmodule Server.A do\n  def go, do: 1\nend\n")
    File.write!(Path.join(repo, "tasks/x.toml"), "[tasks.\"office:golden\"]\n")

    git = fn args -> {_, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"])
    git.(["update-ref", "refs/remotes/origin/main", "HEAD"])
    on_exit(fn -> File.rm_rf!(repo) end)
    %{repo: repo}
  end

  test "finds what origin/main holds", %{repo: repo} do
    assert Probe.found?(repo, {:module, "Server.A"})
    assert Probe.found?(repo, {:function, "go"})
    assert Probe.found?(repo, {:path, "server/lib/a.ex"})
    assert Probe.found?(repo, {:task, "office:golden"})
  end

  test "misses what it does not", %{repo: repo} do
    refute Probe.found?(repo, {:module, "Server.Gone"})
    refute Probe.found?(repo, {:function, "gone"})
    refute Probe.found?(repo, {:path, "server/nope.ex"})
    refute Probe.found?(repo, {:task, "no:task"})
  end

  test "a needle that looks like a flag is data, not an option", %{repo: repo} do
    refute Probe.found?(repo, {:module, "-v"})
  end
end
