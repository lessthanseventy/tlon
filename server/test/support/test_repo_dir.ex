defmodule Server.TestRepoDir do
  @moduledoc """
  A throwaway git repo with one commit, for suites that exercise worktrees end to end
  (`Server.Worktree`, the spawn's `TLON_CWD`, promotion's rename, delete's cleanup). Removed on
  exit. `with_project/1` also registers a workspace + a repo-bearing project pointing at it, so a
  thread opened in that workspace resolves to the repo.
  """

  def make!(context \\ %{}) do
    tmp = Path.join(System.tmp_dir!(), "repo-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    clear_seat_thread()
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

  @doc """
  `Server.Worktree.ensure` points a sibling repo's hooks at tlon's, which refuse a commit on main
  while `TLON_THREAD` is set — as it is in a seat's own env. Cleared for the test, restored on exit.
  """
  def clear_seat_thread do
    seat_thread = System.get_env("TLON_THREAD")
    System.delete_env("TLON_THREAD")
    ExUnit.Callbacks.on_exit(fn -> if seat_thread, do: System.put_env("TLON_THREAD", seat_thread) end)
  end

  def with_project(context \\ %{}) do
    %{repo: repo} = ctx = make!(context)
    {:ok, ws} = Server.Workspaces.register(%{name: "wt-#{System.unique_integer([:positive])}"})

    {:ok, project} =
      Server.Projects.register(%{workspace_id: ws.id, name: "proj", repos: [%{"name" => "r", "path" => repo}]})

    Map.merge(ctx, %{ws: ws, project: project})
  end
end
