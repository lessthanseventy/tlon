defmodule Server.Maintain.StraysTest do
  # A stray worktree is one no thread is working in: no thread, a closed one, or the lobby's (which
  # never finishes, so work parked there is surfaced). The sweep removes a clean one — but never
  # the lobby's, which every coworker's home window runs in.
  use ExUnit.Case, async: false

  alias Server.Maintain.Strays
  alias Server.Worktree

  setup do
    Server.TestDB.clean!()
    repo = Path.join(System.tmp_dir!(), "strays-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repo)
    git = fn args -> System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    {_, 0} = git.(["init", "-q"])
    {_, 0} = git.(["config", "user.email", "test@test"])
    {_, 0} = git.(["config", "user.name", "test"])
    File.write!(Path.join(repo, "README"), "seed\n")
    {_, 0} = git.(["add", "README"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    on_exit(fn -> File.rm_rf!(repo) end)

    {:ok, ws} = Server.Workspaces.register(%{name: "Strays"})
    {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "strays", repos: [%{"path" => repo}]})
    %{repo: repo, ws: ws, project: p}
  end

  test "the sweep removes a closed thread's clean worktree, never the lobby's", %{repo: repo, ws: ws, project: p} do
    {:ok, lobby} =
      Server.Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id, project_id: p.id})

    {:ok, done} = Server.Channel.open_thread(%{title: "done", scope: "machine", workspace_id: ws.id, project_id: p.id})
    {:ok, lobby_wt} = Worktree.ensure(repo, Worktree.name_for(lobby))
    {:ok, done_wt} = Worktree.ensure(repo, Worktree.name_for(done))
    {:ok, _} = Server.Channel.close_thread(done)

    names = for %{name: n} <- Strays.worktrees(), do: n
    assert Worktree.name_for(done) in names
    assert Worktree.name_for(lobby) in names

    Server.Maintain.Sweep.run()
    refute File.exists?(done_wt)
    assert File.exists?(lobby_wt)
  end
end
