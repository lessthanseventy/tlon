defmodule Server.Workspaces do
  @moduledoc """
  The workspaces context (workspaces/orbis Slice 1): the write pipe and reads over the
  `workspace` table. Compositions are DATA here; console reads `all/0` to drive its
  picker/survey/spawn, and every write announces on `Server.Bus`'s workspaces topic so
  those live surfaces refresh. A workspace is machine-global — no thread scope.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Coworker
  alias Server.Policy
  alias Server.Repo
  alias Server.Workspace
  alias Server.WorkspaceAgent
  alias Server.WorkspaceRepo

  @doc "Register a workspace. `{:ok, workspace}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register(attrs) do
    {repos, attrs} = pop_repos(attrs)
    {bench, attrs} = pop_bench(attrs)

    with {:ok, workspace} <- attrs |> Workspace.register_changeset() |> Repo.insert() do
      # every workspace is born with #general (UX slice 1b)
      _ = Server.Channels.general(workspace.id)
      # …and with its scope and its bench as rows (UX slice 5). A template/seed hands both over at
      # birth so a fresh workspace is never a workspace with nowhere to work and nobody to work.
      Enum.each(repos, &add_repo(workspace.id, &1))
      bench |> Enum.with_index() |> Enum.each(fn {entry, i} -> seat(workspace.id, Map.put(entry, :sort, i)) end)
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

  @doc """
  A workspace's BENCH — the coworkers it employs, as `Server.Coworker` structs with `lead?` already
  stamped, in the order the operator arranged them. This is THE roster read: nothing else should be
  joining `workspace_agent` to `agent` and deciding for itself who the lead is.
  """
  @spec bench(integer()) :: [Coworker.t()]
  def bench(workspace_id), do: workspace_id |> bench_query() |> Repo.all() |> to_bench()

  @doc """
  The benches of many workspaces at once, as `%{workspace_id => [coworker]}` — the whole picker in
  ONE query, for the same reason `repos_by_workspace/1` exists.
  """
  @spec bench_by_workspace([integer()]) :: %{integer() => [Coworker.t()]}
  def bench_by_workspace(workspace_ids) do
    from(wa in WorkspaceAgent,
      join: a in Server.Agent,
      on: a.id == wa.agent_id,
      where: wa.workspace_id in ^workspace_ids,
      order_by: [asc: wa.sort, asc: wa.id],
      select: {wa.workspace_id, %{id: wa.id, agent_id: a.id, name: a.name, archetype: wa.archetype, sort: wa.sort}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {ws_id, rows} -> {ws_id, to_bench(rows)} end)
  end

  @doc "A workspace's lead coworker, or nil — `Server.Coworker.lead/1` over its bench, the ONE derivation."
  @spec lead(integer() | nil) :: Coworker.t() | nil
  def lead(nil), do: nil
  def lead(workspace_id), do: workspace_id |> bench() |> Coworker.lead()

  @doc """
  Seat a coworker on a workspace's bench, registering the `agent` if this handle is new — a bench
  you can name is a bench you can point at, so the agent exists from the moment it is seated rather
  than the first time something needs it. `{:ok, coworker}` or `{:error, changeset}`.
  """
  @spec seat(integer(), map()) :: {:ok, Coworker.t()} | {:error, Ecto.Changeset.t()}
  def seat(workspace_id, attrs) do
    attrs = Map.new(attrs)
    name = attrs[:name] || attrs["name"]
    archetype = attrs[:archetype] || attrs["archetype"]

    with {:ok, agent} <- ensure_agent(name, archetype),
         {:ok, row} <-
           %{
             workspace_id: workspace_id,
             agent_id: agent.id,
             archetype: archetype,
             sort: attrs[:sort] || next_seat_sort(workspace_id)
           }
           |> WorkspaceAgent.seat_changeset()
           |> Repo.insert() do
      announce_workspace({:ok, row}, workspace_id)
      {:ok, %Coworker{id: row.id, agent_id: agent.id, name: agent.name, archetype: row.archetype, sort: row.sort}}
    end
  end

  @doc "Unseat a coworker by its bench-row id. The AGENT survives — it is durable identity, and other threads point at it."
  @spec unseat(integer()) :: {:ok, WorkspaceAgent.t()} | {:error, :no_such_seat}
  def unseat(seat_id) do
    case Repo.get(WorkspaceAgent, seat_id) do
      nil ->
        {:error, :no_such_seat}

      %WorkspaceAgent{} = row ->
        # The policy goes with the seat. Left behind it is dead data that comes back to life the
        # moment the coworker is re-seated — an operator who unseats to revoke a yolo flag would
        # silently get it back.
        Repo.delete_all(from p in Policy, where: p.workspace_id == ^row.workspace_id and p.agent_id == ^row.agent_id)

        {:ok, _} = Repo.delete(row)
        announce_workspace({:ok, row}, row.workspace_id)
        {:ok, row}
    end
  end

  @doc """
  Replace a workspace's whole bench with `entries` (`%{name, archetype}` maps, string- or
  atom-keyed). The overwrite semantics the old `roster` JSON column had, kept for the MCP edit tool.
  """
  @spec replace_bench(integer(), [map()]) :: :ok
  def replace_bench(workspace_id, entries) do
    Repo.delete_all(from wa in WorkspaceAgent, where: wa.workspace_id == ^workspace_id)

    entries
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.each(fn {entry, i} -> seat(workspace_id, entry |> Map.new() |> Map.put(:sort, i)) end)

    :ok
  end

  defp bench_query(workspace_id) do
    from(wa in WorkspaceAgent,
      join: a in Server.Agent,
      on: a.id == wa.agent_id,
      where: wa.workspace_id == ^workspace_id,
      order_by: [asc: wa.sort, asc: wa.id],
      select: %{id: wa.id, agent_id: a.id, name: a.name, archetype: wa.archetype, sort: wa.sort}
    )
  end

  defp to_bench(rows), do: rows |> Enum.map(&struct(Coworker, &1)) |> Coworker.mark_lead()

  # A handle is an agent: find it or register it. `mandate` defaults to the archetype and `engine` to
  # local, which is what the lazy `-machine` registration supplied before the suffix retired.
  defp ensure_agent(nil, _archetype), do: {:error, Ecto.Changeset.add_error(%Ecto.Changeset{}, :name, "is required")}

  defp ensure_agent(name, archetype) do
    case Server.Staff.agent_by_name(name) do
      %Server.Agent{} = agent -> {:ok, agent}
      nil -> Server.Staff.register_agent(%{name: name, mandate: archetype || "general", engine: "local"})
    end
  end

  defp next_seat_sort(workspace_id) do
    (Repo.one(from wa in WorkspaceAgent, where: wa.workspace_id == ^workspace_id, select: max(wa.sort)) || -1) + 1
  end

  # `roster:` in the register attrs is the workspace's bench at birth — a list of
  # `%{archetype, name}` maps in either key style (the seed and the templates each use one). Not a
  # workspace column any more, so it comes out before the changeset sees it.
  defp pop_bench(attrs) do
    attrs = Map.new(attrs)
    {bench, attrs} = Map.pop(attrs, :roster, Map.get(attrs, "roster", []))

    {bench |> List.wrap() |> Enum.map(&normalize_seat/1), Map.delete(attrs, "roster")}
  end

  defp normalize_seat(%{} = entry) do
    entry = Map.new(entry)
    %{name: entry[:name] || entry["name"], archetype: entry[:archetype] || entry["archetype"]}
  end

  @doc "The policy for one coworker in one workspace, or nil (inherit everything)."
  @spec policy(integer(), integer()) :: Policy.t() | nil
  def policy(workspace_id, agent_id), do: Repo.get_by(Policy, workspace_id: workspace_id, agent_id: agent_id)

  @doc "A workspace's policies as `%{agent_id => policy}` — one query for a whole CONFIG pane."
  @spec policies(integer()) :: %{integer() => Policy.t()}
  def policies(workspace_id) do
    from(p in Policy, where: p.workspace_id == ^workspace_id)
    |> Repo.all()
    |> Map.new(&{&1.agent_id, &1})
  end

  @doc """
  Merge `attrs` into a (workspace, agent) policy, creating the row if it is the first knob set.
  Setting every knob back to nil DELETES the row: an empty policy and no policy mean the same
  thing, and keeping the empty one would leave "inherit" looking like a decision.
  """
  @spec set_policy(integer(), integer(), map()) :: {:ok, Policy.t() | nil} | {:error, Ecto.Changeset.t()}
  def set_policy(workspace_id, agent_id, attrs) do
    existing = policy(workspace_id, agent_id) || %Policy{workspace_id: workspace_id, agent_id: agent_id}

    with {:ok, saved} <- existing |> Policy.changeset(attrs) |> Repo.insert_or_update() do
      if Policy.empty?(saved) do
        Repo.delete(saved)
        announce_workspace({:ok, saved}, workspace_id)
        {:ok, nil}
      else
        announce_workspace({:ok, saved}, workspace_id)
        {:ok, saved}
      end
    end
  end
end
