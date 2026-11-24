defmodule Server.Projects.Removal do
  @moduledoc """
  Removing a project whose repo the operator deleted, with what only scaffolds it. `plan/1` reads
  what a removal would delete and what holds it; `execute/1` does it in one transaction.

  Born with a project: the memory thread (`Server.Import.Memory`), and with its workspace the
  standing thread (`Server.Bootstrap.ensure_standing/1`, carrying the workspace's default project)
  and `#general`. Those are scaffolding while empty. Anything that carries work holds the removal,
  and nothing it holds is deleted:

    * on a thread: a message, session, fact, issue, todo, question, habit, event, playbook, ticket
      tie, schedule or schedule run, a wake still queued, a child thread, a workline's state (stage,
      slug, awaiting), an agent other than the workspace's lead, or a thread that is not one of the
      two born-with ones;
    * on the project: a ticket;
    * on the workspace, when this is its last project: a thread of its own, a ticket, a topic
      channel, a bench seat or policy, a schedule, routine or quest.

  A workspace that holds other projects stays. Its standing thread belongs to the workspace, so it
  stays too, moved to the workspace's default project among the others.
  """
  import Ecto.Query

  alias Server.Project
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace
  alias Server.WorkspaceRepo

  @hanging [
    {"message", :thread_id, "messages"},
    {"session", :thread_id, "sessions"},
    {"fact", :thread_id, "facts"},
    {"issue", :thread_id, "issues"},
    {"todo", :thread_id, "todos"},
    {"question", :thread_id, "questions"},
    {"event", :thread_id, "events"},
    {"habit", :source_thread_id, "habits"},
    {"playbook", :source_thread_id, "playbooks"},
    {"ticket_thread", :thread_id, "ticket ties"},
    {"schedule", :thread_id, "schedules"},
    {"schedule_run", :thread_id, "schedule runs"},
    {"wake", :thread_id, "queued wakes"},
    {"thread", :parent_thread_id, "child threads"}
  ]

  @typedoc "What a removal would do, in names the operator reads."
  @type plan :: %{
          project: Project.t(),
          workspace: Workspace.t(),
          threads: [Thread.t()],
          repoint: {Thread.t(), Project.t()} | nil,
          repos: [WorkspaceRepo.t()],
          drop_workspace: boolean(),
          blocked: [String.t()],
          paths: [String.t()],
          notes: [String.t() | {:off_main | :drift, String.t()}],
          keep: [String.t()]
        }

  @doc "What removing `project` would do and what holds it. Reads only."
  @spec plan(Project.t()) :: plan()
  def plan(%Project{} = project) do
    workspace = Repo.get!(Workspace, project.workspace_id)
    others = Repo.all(from o in Project, where: o.workspace_id == ^workspace.id and o.id != ^project.id, order_by: o.id)
    drop_workspace = others == []
    standing = Server.Channel.machine_thread(workspace.id)

    {home, owned} =
      project.id
      |> threads_of()
      |> Enum.split_with(&(not drop_workspace and standing != nil and &1.id == standing.id))

    paths = Server.Jobs.KeepUp.exclusive_paths(project)
    {notes, keep} = Server.Jobs.KeepUp.stale(paths)

    %{
      project: project,
      workspace: workspace,
      threads: owned,
      repoint: repoint(home, others, workspace),
      repos: if(drop_workspace, do: Server.Workspaces.repos(workspace.id), else: repos_at(workspace, paths)),
      drop_workspace: drop_workspace,
      blocked: blocked(project, workspace, owned, drop_workspace),
      paths: paths,
      notes: notes,
      keep: keep
    }
  end

  @doc """
  Remove what `plan/1` found, in one transaction: refused with the plan's `blocked` reasons when
  anything holds it, nothing written then. Announces after the commit; the keyed rollout notes and
  keep rows of its repos go with it.
  """
  @spec execute(Project.t()) :: {:ok, plan()} | {:error, {:blocked, [String.t(), ...]}}
  def execute(%Project{} = project) do
    result =
      Repo.transaction(fn ->
        case plan(project) do
          %{blocked: [_ | _] = reasons} -> Repo.rollback({:blocked, reasons})
          plan -> tap(plan, &delete/1)
        end
      end)

    with {:ok, plan} <- result do
      after_commit(plan)
      {:ok, plan}
    end
  end

  defp delete(plan) do
    ids = Enum.map(plan.threads, & &1.id)
    Repo.delete_all(from t in Thread, where: t.id in ^ids)

    with {home, target} <- plan.repoint do
      Repo.update_all(from(t in Thread, where: t.id == ^home.id), set: [project_id: target.id])
    end

    if plan.workspace.default_project_id == plan.project.id and not is_nil(plan.repoint) do
      {_, target} = plan.repoint
      Repo.update_all(from(w in Workspace, where: w.id == ^plan.workspace.id), set: [default_project_id: target.id])
    end

    repo_ids = Enum.map(plan.repos, & &1.id)
    Repo.delete_all(from r in WorkspaceRepo, where: r.id in ^repo_ids)

    if plan.drop_workspace,
      do: Repo.delete_all(from c in Server.ChannelRow, where: c.workspace_id == ^plan.workspace.id)

    Repo.delete!(plan.project)
    if plan.drop_workspace, do: Repo.delete!(plan.workspace)
  end

  defp after_commit(plan) do
    Server.Bus.announce({:ok, plan.project}, :project_removed)

    if plan.drop_workspace do
      :persistent_term.erase({Server.Office, :windows, plan.workspace.id})
      Server.Bus.announce({:ok, plan.workspace}, :workspace_removed)
    end

    Server.Jobs.KeepUp.forget(plan.notes, plan.keep)
  end

  defp threads_of(project_id), do: Repo.all(from t in Thread, where: t.project_id == ^project_id, order_by: t.id)

  defp repoint([], _others, _workspace), do: nil

  defp repoint([%Thread{} = home | _], [first | _] = others, %Workspace{default_project_id: default}) do
    {home, Enum.find(others, first, &(&1.id == default))}
  end

  defp repos_at(workspace, paths),
    do: Enum.filter(Server.Workspaces.repos(workspace.id), &(Path.expand(&1.path) in paths))

  defp blocked(project, workspace, threads, drop_workspace) do
    lead = Server.Channel.designated_lead(workspace.id)

    Enum.flat_map(threads, &thread_holds(&1, lead)) ++
      holds("project", [{"ticket", :project_id, project.id, "tickets"}]) ++
      if(drop_workspace, do: workspace_holds(project, workspace), else: [])
  end

  defp thread_holds(%Thread{} = t, lead) do
    own =
      [
        if(!born_with?(t), do: "is not one of its two born-with threads"),
        if(t.stage || t.slug || t.awaiting, do: "carries workline state (stage #{t.stage}, awaiting #{t.awaiting})"),
        if(t.agent_id not in [nil, lead], do: "is assigned to agent ##{t.agent_id}, not the workspace's lead")
      ] ++ for {table, column, label} <- @hanging, n = count(table, column, t.id), n > 0, do: "holds #{n} #{label}"

    for why <- own, why, do: ~s(thread ##{t.id} "#{t.title}" #{why})
  end

  defp born_with?(%Thread{scope: "machine", title: title}) do
    title in [Server.Bootstrap.standing_title(), Server.Import.Memory.thread_title()]
  end

  defp born_with?(_thread), do: false

  defp workspace_holds(%Project{id: project_id}, %Workspace{id: id}) do
    elsewhere = fn schema ->
      from r in schema, where: r.workspace_id == ^id and (is_nil(r.project_id) or r.project_id != ^project_id)
    end

    topics = from c in Server.ChannelRow, where: c.workspace_id == ^id and c.kind != "general"

    rows =
      for {label, query} <- [
            {"threads of its own", elsewhere.(Thread)},
            {"tickets of its own", elsewhere.(Server.Ticket)},
            {"topic channels", topics}
          ],
          n = Repo.aggregate(query, :count),
          n > 0,
          do: "workspace holds #{n} #{label}"

    rows ++
      holds("workspace", [
        {"workspace_agent", :workspace_id, id, "bench seats"},
        {"workspace_policy", :workspace_id, id, "seat policies"},
        {"schedule", :workspace_id, id, "schedules"},
        {"routine", :workspace_id, id, "routines"},
        {"quest", :workspace_id, id, "quests"}
      ])
  end

  defp holds(who, specs) do
    for {table, column, id, label} <- specs, n = count(table, column, id), n > 0, do: "#{who} holds #{n} #{label}"
  end

  defp count(table, column, id) do
    Repo.one(from r in table, where: field(r, ^column) == ^id, select: count())
  end
end
