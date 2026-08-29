defmodule Server.Workspaces do
  @moduledoc """
  The workspaces context (workspaces/orbis Slice 1): the write pipe and reads over the
  `workspace` table. Compositions are DATA here; aleph reads `all/0` to drive its
  picker/survey/spawn, and every write announces on `Server.Bus`'s workspaces topic so
  those live surfaces refresh. A workspace is machine-global — no thread scope.
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Repo
  alias Server.Workspace

  @doc "Register a workspace. `{:ok, workspace}` or `{:error, changeset}` (e.g. a duplicate name)."
  def register(attrs) do
    attrs |> Workspace.register_changeset() |> Repo.insert() |> Bus.announce(:workspace_registered)
  end

  @doc "Every workspace, newest-first (by id) — the read aleph's Orbis survey/picker maps over."
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
    Repo.update_all(from(t in Server.Thread, where: t.workspace_id == ^workspace.id),
      set: [workspace_id: heir.id]
    )

    # A delete refusal must roll the rehousing back with it — without this, a future
    # table gaining a workspace FK would silently move threads while the workspace survives.
    case Repo.delete(workspace) do
      {:ok, removed} -> removed
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end
end
