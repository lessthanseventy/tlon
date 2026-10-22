defmodule Server.Workline.ArtifactsBaseTest do
  # A workline's change is measured from origin/main, not from whatever the main checkout has
  # checked out: on a stale branch there, HEAD...work/<slug> counted main's own newer commits as the
  # workline's (a 7-file change read as 105 files, "a migration" and "yours to judge").
  use ExUnit.Case, async: false

  alias Server.Workline.Artifacts.Git

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    Server.TestDB.clean!()
    sh = fn cmd -> {_, 0} = System.cmd("sh", ["-c", cmd], cd: tmp, stderr_to_stdout: true) end
    sh.("git init -q --bare origin.git && git clone -q origin.git repo")
    repo = Path.join(tmp, "repo")

    run = fn cmd -> {_, 0} = System.cmd("sh", ["-c", cmd], cd: repo, stderr_to_stdout: true) end

    run.("""
    git config user.email t@t && git config user.name t && echo a >a.txt && git add a.txt && git commit -qm a &&
    git branch -M main && git branch stale && echo b >b.txt && mkdir -p server/priv && echo m >server/priv/migration.exs &&
    git add -A && git commit -qm "main moves on" && git push -q origin main &&
    git checkout -qb work/x && echo c >c.txt && git add c.txt && git commit -qm "the workline" && git checkout -q stale
    """)

    {:ok, ws} = Server.Workspaces.register(%{name: "base-#{System.unique_integer([:positive])}"})
    {:ok, _} = Server.Projects.register(%{workspace_id: ws.id, name: "p", repos: [%{"name" => "r", "path" => repo}]})
    {:ok, t} = Server.Workline.open(%{title: "x", slug: "x", stage: "build", workspace_id: ws.id})
    %{t: t}
  end

  test "changed_paths, diffstat and change count only the workline's own change", %{t: t} do
    assert Git.changed_paths(t) == ["c.txt"]
    assert {:ok, stat} = Git.diffstat(t)
    assert stat =~ "1 file changed"
    assert %{paths: ["c.txt"]} = Git.change(t)
  end

  test "the branch check sees the workline's code", %{t: t} do
    assert {:ok, _} = Git.check(t, :branch)
  end
end
