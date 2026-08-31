defmodule Server.Bootstrap do
  @moduledoc """
  Boot-time integrity (reshape slice A). Two invariants, restored on every start:
  a default workspace exists, and every thread points at a workspace that is real.
  Replaces the flake's ExecStartPre seed AND console's hardcoded fallback workspace —
  any node that boots the server app self-heals, including the dev scratch db.

  Repair targets drift the FK pragma can't catch after the fact: table-rebuild
  migrations and pre-integrity `remove_workspace` both left threads pointing at dead
  workspace ids (observed live: a thread → workspace 5 with only workspace 1 existing).
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Project
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace
  alias Server.Workspaces

  require Logger

  # The default project every workspace gets (Workspace ▸ Project ▸ Thread, 2026-08-30) — the
  # home for threads that predate the project tier or were opened without one.
  @default_project "general"

  @default %{
    name: "ficciones",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "builder", "name" => "hronir"},
      %{"archetype" => "reviewer", "name" => "reviewer"},
      %{"archetype" => "planner", "name" => "planner"}
    ]
  }

  @doc """
  Seed-if-empty + repair. Returns `{:ok, default_workspace}` — the oldest workspace, which
  is the default home for adrift threads. Idempotent; an operator's workspaces and
  any thread already housed in a live workspace are never touched.
  """
  @spec ensure() :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()}
  def ensure do
    with {:ok, workspace} <- default_workspace() do
      repair(workspace)
      repair_projects()
      repair_machine_roots()
      # Base self-knowledge + baseline projects (2026-08-31) — idempotent, so a reset/fresh scratch
      # DB heals to "funes already knows the basics" on the next boot. Absorbs its own failures.
      Server.Seed.ensure_safe()
      {:ok, workspace}
    end
  end

  @doc """
  `ensure/0` for the supervision tree: any raise/exit (schema not yet migrated on
  a first boot, repo briefly down) is absorbed to `:skipped` — bootstrap must
  never take the app down with it. Every non-ok outcome is LOGGED: a broken
  bootstrap would otherwise present exactly like honest server-down (Orbis-only
  picker) with no diagnostic anywhere.
  """
  @spec ensure_safe() :: {:ok, Workspace.t()} | {:error, Ecto.Changeset.t()} | :skipped
  def ensure_safe do
    case ensure() do
      {:ok, _workspace} = ok ->
        ok

      {:error, reason} = error ->
        Logger.warning("Server.Bootstrap: seed failed — #{inspect(reason)}; repair skipped this boot")
        error
    end
  rescue
    e ->
      Logger.warning("Server.Bootstrap: skipped — #{Exception.message(e)}")
      :skipped
  catch
    :exit, reason ->
      Logger.warning("Server.Bootstrap: skipped — exit #{inspect(reason)}")
      :skipped
  end

  @doc """
  Supervision-tree entry: runs `ensure_safe/0` SYNCHRONOUSLY during child startup and
  returns `:ignore` — the supervisor only proceeds to later children (consult mirror,
  MCP/Bandit) once seed + repair are done, so nothing serves against an unseeded db.
  A `{Task, fun}` child would return immediately and leave a serve-before-seed window.
  """
  def start_link do
    ensure_safe()
    :ignore
  end

  @doc false
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, restart: :temporary}
  end

  defp default_workspace do
    case Repo.one(from w in Workspace, order_by: [asc: w.id], limit: 1) do
      nil -> Workspaces.register(@default)
      %Workspace{} = workspace -> {:ok, workspace}
    end
  end

  @doc """
  The default workspace's id — the oldest workspace, or nil when none exists yet
  (a pre-bootstrap open proceeds unhoused; the boot repair houses it). The
  open-thread paths call this so every new thread has a home from birth.
  """
  @spec default_workspace_id() :: integer() | nil
  def default_workspace_id do
    Repo.one(from w in Workspace, order_by: [asc: w.id], limit: 1, select: w.id)
  end

  # One UPDATE: every thread whose workspace_id is NULL or names no live workspace moves
  # to the default. Runs with FKs on — the target id is real by construction.
  defp repair(%Workspace{id: id}) do
    live = from(w in Workspace, select: w.id)

    adrift = from(t in Thread, where: is_nil(t.workspace_id) or t.workspace_id not in subquery(live))
    Repo.update_all(adrift, set: [workspace_id: id])
  end

  # The project tier (2026-08-30): every workspace gets a `general` project, and every thread
  # with no project moves to its workspace's `general`. Runs AFTER repair/1, so `workspace_id` is
  # already real. Idempotent — an existing `general` and any thread already in a project are left.
  defp repair_projects do
    defaults =
      Repo.all(Workspace)
      |> Map.new(fn ws -> {ws.id, ensure_default_project(ws).id} end)

    for {workspace_id, project_id} <- defaults do
      unhoused = from(t in Thread, where: t.workspace_id == ^workspace_id and is_nil(t.project_id))
      Repo.update_all(unhoused, set: [project_id: project_id])
    end
  end

  # Every workspace gets exactly one open, stage-less machine root — the coordination "general" chat
  # the cockpit's center thread-stack scopes to (per-workspace re-scope, 2026-08-31). Runs AFTER
  # repair_projects so the root can carry the default project. Idempotent: a workspace that already
  # has a machine root is left untouched.
  defp repair_machine_roots do
    for ws <- Repo.all(Workspace), is_nil(Channel.machine_thread(ws.id)) do
      project = ensure_default_project(ws)

      Channel.open_thread(%{
        title: @default_project,
        scope: "machine",
        workspace_id: ws.id,
        project_id: project.id
      })
    end
  end

  defp ensure_default_project(%Workspace{} = ws) do
    case Projects.by_name(ws.id, @default_project) do
      %Project{} = project ->
        project

      nil ->
        {:ok, project} = Projects.register(%{workspace_id: ws.id, name: @default_project, repos: workspace_repos(ws)})
        project
    end
  end

  # The workspace's git-tracked globs become the default project's repos (name defaults to the glob).
  defp workspace_repos(%Workspace{paths: paths}) when is_list(paths), do: Enum.map(paths, &%{"path" => &1})
  defp workspace_repos(_ws), do: []
end
