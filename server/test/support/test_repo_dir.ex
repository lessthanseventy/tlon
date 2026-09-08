defmodule Server.TestRepoDir do
  @moduledoc """
  A throwaway git repo with one commit, for suites that exercise worktrees end to end
  (`Server.Worktree`, the spawn's `TLON_CWD`, promotion's rename, delete's cleanup). Removed on
  exit. `with_project/1` also registers a workspace + a repo-bearing project pointing at it, so a
  thread opened in that workspace resolves to the repo.
  """

  def make!(context \\ %{}) do
    tmp = Path.join(System.tmp_dir!(), "repo-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    git = fn args -> System.cmd("git", ["-C", tmp | args], stderr_to_stdout: true) end
    {_, 0} = git.(["init", "-q"])
    {_, 0} = git.(["config", "user.email", "test@test"])
    {_, 0} = git.(["config", "user.name", "test"])
    File.write!(Path.join(tmp, "README"), "seed\n")
    {_, 0} = git.(["add", "README"])
    {_, 0} = git.(["commit", "-qm", "seed"])
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(tmp) end)
    Map.merge(context, %{repo: tmp, git: git})
  end

  def with_project(context \\ %{}) do
    %{repo: repo} = ctx = make!(context)
    {:ok, ws} = Server.Workspaces.register(%{name: "wt-#{System.unique_integer([:positive])}"})

    {:ok, project} =
      Server.Projects.register(%{workspace_id: ws.id, name: "proj", repos: [%{"name" => "r", "path" => repo}]})

    Map.merge(ctx, %{ws: ws, project: project})
  end
end
