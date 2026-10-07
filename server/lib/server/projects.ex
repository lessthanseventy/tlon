defmodule Server.Projects do
  @moduledoc """
  The projects context (Workspace ▸ Project ▸ Thread): the write pipe
  (changeset |> insert |> Bus.announce) and reads over the `project` table. A project is
  the middle tier — it belongs to a workspace and owns threads. Every write announces on
  `Server.Bus`'s projects topic so live surfaces refresh. The DB is the bus
  (§10): assertions read back through it.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Project
  alias Server.Repo

  @doc "Register a project under a workspace. `{:ok, project}` or `{:error, changeset}` (dup name within the workspace / bad workspace_id)."
  def register(attrs) do
    attrs |> Project.register_changeset() |> Repo.insert() |> Bus.announce(:project_registered)
  end

  @doc "Projects in one workspace, oldest-first (the switcher's stable order)."
  def in_workspace(workspace_id) do
    Repo.all(from p in Project, where: p.workspace_id == ^workspace_id, order_by: [asc: p.id])
  end

  @doc """
  The project a new thread in this workspace defaults to: the one the operator last posted in, or
  nil when he has posted in none. By message, not by thread: the machine opens threads too (an
  import's memory thread), and those are not the operator using a project.
  """
  def last_used(workspace_id) do
    operator = Application.get_env(:server, :operator, "andrew")

    Repo.one(
      from m in Server.Message,
        join: t in Server.Thread,
        on: t.id == m.thread_id,
        where: t.workspace_id == ^workspace_id and not is_nil(t.project_id) and m.author == ^operator,
        order_by: [desc: m.created_at, desc: m.id],
        limit: 1,
        select: t.project_id
    )
  end

  @doc "A project by id, or nil."
  def get(id), do: Repo.get(Project, id)

  @doc "A project by (workspace_id, name), or nil — the find-or-create + seed lookup."
  def by_name(workspace_id, name), do: Repo.get_by(Project, workspace_id: workspace_id, name: name)

  @doc "The workspace's default project (where a thread with no project lands), or nil when unset."
  def default(workspace_id) do
    Repo.one(
      from p in Project,
        join: w in Server.Workspace,
        on: w.default_project_id == p.id,
        where: w.id == ^workspace_id
    )
  end

  @doc "Edit a project's mutable fields (`name`/`repos`/`knobs`). `{:ok, project}` or `{:error, changeset}`."
  def edit(%Project{} = project, attrs) do
    project |> Project.edit_changeset(attrs) |> Repo.update() |> Bus.announce(:project_edited)
  end

  @doc """
  Remove a project. Refused (`{:error, :has_threads}`) while any thread still belongs to it —
  a project never orphans a thread's `project_id`. Move or delete its threads first.
  """
  def remove(%Project{} = project) do
    if Repo.exists?(from t in Server.Thread, where: t.project_id == ^project.id) do
      {:error, :has_threads}
    else
      project |> Repo.delete() |> Bus.announce(:project_removed)
    end
  end

  @doc "Move a thread into another project of its own workspace."
  @spec move_thread(Server.Thread.t(), integer()) ::
          {:ok, Server.Thread.t()} | {:error, :no_project | :other_workspace | Ecto.Changeset.t()}
  def move_thread(%Server.Thread{} = thread, project_id) do
    case get(project_id) do
      nil ->
        {:error, :no_project}

      %Project{workspace_id: wid} when wid != thread.workspace_id ->
        {:error, :other_workspace}

      _project ->
        thread
        |> Ecto.Changeset.change(project_id: project_id)
        |> Repo.update()
        |> Bus.announce(:thread_moved)
    end
  end

  @doc """
  Resolve a thread to the repo dir its work lives in (the worktree/lazygit base). The thread's own
  `repo` when it names one; else its project's first repo (or `:no_repo` — never silently borrows
  another project's); a thread with no project falls back to the workspace's first repo-bearing
  project. `{:ok, expanded_path}` or `{:error, :no_repo}`. The path is `~`-expanded but not checked
  for existence — the caller (`Server.Worktree`) reports a bad tree honestly.
  """
  def repo_for_thread(%Server.Thread{repo: repo}) when is_binary(repo), do: {:ok, Path.expand(repo)}

  def repo_for_thread(%Server.Thread{project_id: pid}) when not is_nil(pid) do
    pid |> get() |> primary_repo_path()
  end

  def repo_for_thread(%Server.Thread{workspace_id: wid}) when not is_nil(wid) do
    wid
    |> in_workspace()
    |> Enum.find_value({:error, :no_repo}, fn project ->
      case primary_repo_path(project) do
        {:ok, _} = ok -> ok
        {:error, _} -> false
      end
    end)
  end

  def repo_for_thread(_thread), do: {:error, :no_repo}

  @doc """
  The thread's project's OTHER checkouts, `~`-expanded: what its coworker may read but not write
  (the harness opens them beside the worktree). Never the thread's own repo, never a scope glob;
  `[]` for a thread with no project.
  """
  def read_dirs(%Server.Thread{project_id: pid} = thread) when not is_nil(pid) do
    own = with {:ok, path} <- repo_for_thread(thread), do: path

    for %{"path" => path} <- get(pid).repos || [],
        not String.contains?(path, "*"),
        dir = Path.expand(path),
        dir != own,
        do: dir
  end

  def read_dirs(_thread), do: []

  # The first repo's `~`-expanded path, or `:no_repo`. Repos are a JSON list of `%{"path" => …}`.
  @doc "A project's primary checkout (its first repo), `~`-expanded."
  def primary_repo_path(%Project{repos: [%{"path" => path} | _]}) when is_binary(path) do
    # a workspace scope glob ("modules/*") is not a checkout; expanded, it rooted worktrees in $HOME
    if String.contains?(path, "*"), do: {:error, :no_repo}, else: {:ok, Path.expand(path)}
  end

  def primary_repo_path(_project), do: {:error, :no_repo}
end
