defmodule Server.Projects do
  @moduledoc """
  The projects context (Workspace ▸ Project ▸ Thread, 2026-08-30): the write pipe
  (changeset |> insert |> Bus.announce) and reads over the `project` table. A project is
  the middle tier — it belongs to a workspace and owns threads. Every write announces on
  `Server.Bus`'s projects topic so the console's switcher/rail refresh. The DB is the bus
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

  @doc "Every project, newest-first (by id)."
  def all do
    Repo.all(from p in Project, order_by: [desc: p.id])
  end

  @doc "Projects in one workspace, oldest-first (the switcher's stable order)."
  def in_workspace(workspace_id) do
    Repo.all(from p in Project, where: p.workspace_id == ^workspace_id, order_by: [asc: p.id])
  end

  @doc "A project by id, or nil."
  def get(id), do: Repo.get(Project, id)

  @doc "A project by (workspace_id, name), or nil — the find-or-create + seed lookup."
  def by_name(workspace_id, name), do: Repo.get_by(Project, workspace_id: workspace_id, name: name)

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
end
