defmodule Mix.Tasks.Server.BenchContrastTest do
  use ExUnit.Case, async: true

  test "paths/1 is what the branch changed against origin/main" do
    repo = Path.join(System.tmp_dir!(), "contrast-paths-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    on_exit(fn -> File.rm_rf!(repo) end)
    git = &({_, 0} = System.cmd("git", ["-c", "user.name=t", "-c", "user.email=t@l" | &1], cd: repo))

    git.(["init", "-q"])
    File.write!(Path.join(repo, "a.txt"), "a")
    git.(["add", "-A"])
    git.(["commit", "-qm", "base"])
    git.(["update-ref", "refs/remotes/origin/main", "HEAD"])
    repo |> Path.join("server/lib/server/profiles.ex") |> tap(&File.mkdir_p!(Path.dirname(&1))) |> File.write!("p")
    git.(["add", "-A"])
    git.(["commit", "-qm", "edit"])

    assert Mix.Tasks.Server.BenchContrast.paths(repo) == ["server/lib/server/profiles.ex"]
  end
end
