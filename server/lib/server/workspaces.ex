defmodule Server.Workspaces do
  @moduledoc """
  The workspaces context (workspaces/orbis Slice 1): the write pipe and reads over the
  `workspace` table. Compositions are DATA here; console reads `all/0` to drive its
  picker/survey/spawn, and every write announces on `Server.Bus`'s workspaces topic so
  those live surfaces refresh. A workspace is machine-global — no thread scope.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Repo
  alias Server.Workspace
  alias Server.WorkspaceRepo

  @doc "Register a workspace. `{:ok, workspace}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register(attrs) do
    {repos, attrs} = pop_repos(attrs)

    with {:ok, workspace} <- attrs |> Workspace.register_changeset() |> Repo.insert() do
      # every workspace is born with #general (UX slice 1b)
      _ = Server.Channels.general(workspace.id)
      # …and with its scope as rows (UX slice 5). A template/seed hands them over at birth so a
      # fresh workspace is never a workspace with nowhere to work.
      Enum.each(repos, &add_repo(workspace.id, &1))
      Bus.announce({:ok, workspace}, :workspace_registered)
    end
  end

  @doc "Every workspace, newest-first (by id) — the read console's Orbis survey/picker maps over."
  def all do
    Repo.all(from w in Workspace, order_by: [desc: w.id])
  end

  @doc "A workspace by id, or nil."
  def get(id), do: Repo.get(Workspace, id)

  @doc "A workspace by its unique name, or nil — the find-or-create + seed lookup."
  def by_name(name), do: Repo.get_by(Workspace, name: name)

  @doc "Edit a workspace's mutable fields. `{:ok, workspace}` or `{:error, changeset}`."
  def edit(%Workspace{} = workspace, attrs) do
    workspace |> Workspace.edit_changeset(attrs) |> Repo.update() |> Bus.announce(:workspace_edited)
  end

  @doc """
  Remove a workspace. Its threads are rehoused in the oldest remaining workspace first —
  a remove must never orphan a thread's `workspace_id` (the pre-integrity version did,
  and the dangling refs surfaced as phantom workspaces). The last workspace is refused
  (`{:error, :last_workspace}`): threads always have a home.
  """
  def remove(%Workspace{} = workspace) do
    heir = Repo.one(from w in Workspace, where: w.id != ^workspace.id, order_by: [asc: w.id], limit: 1)

    if heir do
      fn -> rehouse_and_delete(workspace, heir) end
      |> Repo.transaction()
      |> Bus.announce(:workspace_removed)
    else
      {:error, :last_workspace}
    end
  end

  defp rehouse_and_delete(workspace, heir) do
    # the heir's #general takes the threads (a channel belongs to one workspace); then the
    # removed workspace's channels go, so its row can
    home = Server.Channels.general(heir.id)

    Repo.update_all(from(t in Server.Thread, where: t.workspace_id == ^workspace.id),
      set: [workspace_id: heir.id, channel_id: home.id]
    )

    Repo.delete_all(from(c in Server.ChannelRow, where: c.workspace_id == ^workspace.id))

    # A delete refusal must roll the rehousing back with it — without this, a future
    # table gaining a workspace FK would silently move threads while the workspace survives.
    case Repo.delete(workspace) do
      {:ok, removed} -> removed
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  A workspace's repos, in the order the operator arranged them (`sort` ascending). The CONFIG
  pane's sub-list and every "what is this workspace's scope" read go through here.
  """
  @spec repos(integer()) :: [WorkspaceRepo.t()]
  def repos(workspace_id),
    do: Repo.all(from r in WorkspaceRepo, where: r.workspace_id == ^workspace_id, order_by: [asc: r.sort, asc: r.id])

  @doc """
  The repos of many workspaces at once, as `%{workspace_id => [repo]}` — the whole picker in ONE
  query. A query per workspace is how a survey over a dozen workspaces gets slow, and the console
  cache rebuilds this on every workspaces announcement.
  """
  @spec repos_by_workspace([integer()]) :: %{integer() => [WorkspaceRepo.t()]}
  def repos_by_workspace(workspace_ids) do
    from(r in WorkspaceRepo, where: r.workspace_id in ^workspace_ids, order_by: [asc: r.sort, asc: r.id])
    |> Repo.all()
    |> Enum.group_by(& &1.workspace_id)
  end

  @doc """
  Add a repo to a workspace; it lands at the BOTTOM of the list. `{:ok, repo}` or
  `{:error, changeset}` (a duplicate path in the same workspace).
  """
  @spec add_repo(integer(), map()) :: {:ok, WorkspaceRepo.t()} | {:error, Ecto.Changeset.t()}
  def add_repo(workspace_id, attrs) do
    attrs
    |> Map.new()
    |> Map.put(:workspace_id, workspace_id)
    |> Map.put_new_lazy(:sort, fn -> next_repo_sort(workspace_id) end)
    |> WorkspaceRepo.add_changeset()
    |> Repo.insert()
    |> announce_workspace(workspace_id)
  end

  @doc "Edit a repo row (path, remote, default branch). `{:ok, repo}` or `{:error, changeset}`."
  @spec edit_repo(WorkspaceRepo.t(), map()) :: {:ok, WorkspaceRepo.t()} | {:error, Ecto.Changeset.t()}
  def edit_repo(%WorkspaceRepo{} = repo, attrs) do
    repo |> WorkspaceRepo.edit_changeset(attrs) |> Repo.update() |> announce_workspace(repo.workspace_id)
  end

  @doc "Remove a repo row. `{:ok, repo}`."
  @spec remove_repo(WorkspaceRepo.t()) :: {:ok, WorkspaceRepo.t()} | {:error, Ecto.Changeset.t()}
  def remove_repo(%WorkspaceRepo{} = repo), do: repo |> Repo.delete() |> announce_workspace(repo.workspace_id)

  # A repo row is a JOIN-shaped row: the Bus matches on the struct it is handed, and its set is
  # deliberately closed (announcing a join row is a FunctionClauseError — the Bus telling the truth
  # about its contract, same as ticket_link's). So a repo change announces the WORKSPACE it changed.
  defp announce_workspace({:ok, _row} = ok, workspace_id) do
    case Repo.get(Workspace, workspace_id) do
      %Workspace{} = workspace -> Bus.announce({:ok, workspace}, :workspace_edited)
      nil -> :ok
    end

    ok
  end

  defp announce_workspace(other, _workspace_id), do: other

  defp next_repo_sort(workspace_id) do
    (Repo.one(from r in WorkspaceRepo, where: r.workspace_id == ^workspace_id, select: max(r.sort)) || -1) + 1
  end

  # `repos:` in the register attrs is the workspace's scope at birth — a list of `%{path, …}` maps,
  # or bare path strings (what `paths` used to be, so a seed reads the same). It is NOT a workspace
  # column, so it comes out before the changeset ever sees it.
  defp pop_repos(attrs) do
    attrs = Map.new(attrs)
    {repos, attrs} = Map.pop(attrs, :repos, Map.get(attrs, "repos", []))

    {Enum.map(List.wrap(repos), &repo_attrs/1), Map.delete(attrs, "repos")}
  end

  defp repo_attrs(path) when is_binary(path), do: %{path: path}
  defp repo_attrs(%{} = attrs), do: attrs

  @doc """
  Replace a workspace's whole scope with `repos` (paths, or `%{path, remote, default_branch}`
  maps). The overwrite semantics the old `paths` JSON column had, kept for the MCP edit tool: an
  agent that says "the scope is these three" means these three and not these three plus whatever
  was there. One announcement, not one per row.
  """
  @spec replace_repos(integer(), [String.t() | map()]) :: :ok
  def replace_repos(workspace_id, repos) do
    Repo.delete_all(from r in WorkspaceRepo, where: r.workspace_id == ^workspace_id)

    repos
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.each(fn {repo, i} ->
      repo |> repo_attrs() |> Map.put(:sort, i) |> then(&add_repo(workspace_id, &1))
    end)

    :ok
  end

  @doc "One repo row by id, or nil — the CONFIG pane's delete resolves the row it is deleting."
  @spec get_repo(integer()) :: WorkspaceRepo.t() | nil
  def get_repo(id), do: Repo.get(WorkspaceRepo, id)
end
