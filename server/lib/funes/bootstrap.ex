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

  alias Server.Repo
  alias Server.Thread
  alias Server.Workspace
  alias Server.Workspaces

  require Logger

  @default %{
    name: "ficciones",
    type: "code",
    scope: "machine",
    paths: ["modules/*"],
    roster: [
      %{"archetype" => "surveyor", "name" => "tertius"},
      %{"archetype" => "builder", "name" => "hronir"}
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
end
