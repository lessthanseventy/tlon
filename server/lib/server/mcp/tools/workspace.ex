defmodule Server.MCP.Tool.RegisterWorkspace do
  @moduledoc """
  Register a WORKSPACE — a first-class composition (workspaces/orbis Slice 1): a git-tracked
  scope (`paths`), a `roster` of archetype instances, and free-form `knobs` that console
  reads to drive its picker/survey/spawn. Unlike the thread-scoped tools this is
  machine-GLOBAL — it takes no identity, it writes the shared `workspace` table via
  `Server.Workspaces`. `name` is unique; a duplicate is a graceful error, not a crash.
  """
  use Server.MCP.Tool

  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace's unique name"
    field :type, :enum, values: ["code", "life", "blank"], default: "code"
    field :scope, :enum, values: ["project", "machine"], default: "machine"
    field :paths, {:list, :string}, default: [], description: "Git-tracked scope globs"
    field :roster, {:list, :map}, default: [], description: "Archetype instances: {archetype,name,model?,knobs}"
    field :knobs, :map, default: %{}, description: "Free-form per-workspace settings"
  end

  @impl true
  def execute(params, frame) do
    reply(frame, Workspaces.register(params), fn w -> %{"workspace_id" => w.id, "name" => w.name} end)
  end
end

defmodule Server.MCP.Tool.ListWorkspaces do
  @moduledoc """
  Every WORKSPACE, newest-first — the machine-global read console's Orbis survey/picker maps
  over. Takes no identity: workspaces are not thread-scoped.
  """
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.Workspaces

  schema do
  end

  @impl true
  def execute(_params, frame), do: ok(frame, Enum.map(Workspaces.all(), &MCP.Brief.workspace/1))
end

defmodule Server.MCP.Tool.EditWorkspace do
  @moduledoc """
  Edit a WORKSPACE's mutable fields (`type`/`scope`/`paths`/`roster`/`knobs`), identified by
  its unique `name` — a workspace's identity is immutable, so name is the handle, not a
  field this rewrites. Machine-global; a missing workspace is refused rather than created.
  """
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace to edit (its unique name)"
    field :type, :enum, values: ["code", "life", "blank"]
    field :scope, :enum, values: ["project", "machine"]
    field :paths, {:list, :string}, description: "Git-tracked scope globs"
    field :roster, {:list, :map}, description: "Archetype instances: {archetype,name,model?,knobs}"
    field :knobs, :map, description: "Free-form per-workspace settings"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.by_name(params[:name]) do
      nil -> fail(frame, "no such workspace: #{params[:name]}")
      workspace -> reply(frame, Workspaces.edit(workspace, params), &MCP.Brief.workspace/1)
    end
  end
end

defmodule Server.MCP.Tool.RemoveWorkspace do
  @moduledoc """
  Remove a WORKSPACE by its unique `name` — machine-global, thread-independent. A missing
  workspace is refused rather than reported as removed.
  """
  use Server.MCP.Tool

  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace to remove (its unique name)"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.by_name(params[:name]) do
      nil ->
        fail(frame, "no such workspace: #{params[:name]}")

      workspace ->
        case Workspaces.remove(workspace) do
          {:ok, removed} ->
            ok(frame, %{"removed" => removed.name})

          {:error, :last_workspace} ->
            fail(frame, "refused: #{workspace.name} is the last workspace — threads must have a home")
        end
    end
  end
end

defmodule Server.MCP.Tool.RegisterProject do
  @moduledoc """
  Register a PROJECT in the current workspace (the middle tier: Workspace ▸ Project ▸ Thread) —
  a named effort spanning one or more repos. Workspace-scoped via the bound thread; `name` is
  unique within the workspace.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool
  alias Server.Projects

  schema do
    field :name, :string, required: true, description: "The project's name (unique in the workspace)"
    field :repos, {:list, :map}, default: [], description: "Repos: {name, path, url?}"
    field :knobs, :map, default: %{}, description: "Free-form per-project settings"
  end

  @impl true
  def execute(params, frame) do
    case Tool.workspace_of(Identity.from_frame(frame)) do
      nil ->
        fail(frame, "no workspace bound to this session")

      workspace_id ->
        params
        |> Map.put(:workspace_id, workspace_id)
        |> Projects.register()
        |> then(&reply(frame, &1, fn project -> %{"project_id" => project.id, "name" => project.name} end))
    end
  end
end

defmodule Server.MCP.Tool.FileTicket do
  @moduledoc """
  File a TICKET into the current workspace's lightweight tracker — the 2-second capture ("this
  is fucked, file it") that does NOT spin up a thread. Workspace-scoped (resolved from the bound
  thread). Lands at `backlog`; promote it into a thread later when work starts.
  """
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.MCP.Tool
  alias Server.Tickets

  schema do
    field :title, :string, required: true, description: "What the ticket is about (one line)"
    field :body, :string, default: "", description: "Details, optional"
    field :priority, :enum, values: ["low", "med", "high"], default: "med"
    field :labels, {:list, :string}, default: [], description: "Freeform labels"
    field :assignee, :string, description: "Who it's for (an agent handle or the operator), optional"
  end

  @impl true
  def execute(params, frame) do
    case Tool.workspace_of(Identity.from_frame(frame)) do
      nil -> fail(frame, "no workspace bound to this session")
      workspace_id -> reply(frame, Tickets.file(Map.put(params, :workspace_id, workspace_id)), &MCP.Brief.ticket/1)
    end
  end
end

defmodule Server.MCP.Tool.ListTickets do
  @moduledoc "Open tickets in the current workspace's tracker (newest-first), the board reads. Workspace-scoped via the bound thread."
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.MCP.Tool
  alias Server.Tickets

  schema do
    field :include_done, :boolean, default: false, description: "Include done tickets (default: only open)"
  end

  @impl true
  def execute(params, frame) do
    case Tool.workspace_of(Identity.from_frame(frame)) do
      nil ->
        fail(frame, "no workspace bound to this session")

      workspace_id ->
        tickets =
          if params[:include_done],
            do: Tickets.in_workspace(workspace_id),
            else: Tickets.open_in_workspace(workspace_id)

        ok(frame, Enum.map(tickets, &MCP.Brief.ticket/1))
    end
  end
end

defmodule Server.MCP.Tool.UpdateTicket do
  @moduledoc "Update a ticket's status/priority/title/body/assignee. `id` identifies it; a missing ticket is refused."
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.Tickets

  schema do
    field :id, :integer, required: true, description: "The ticket id"
    field :status, :enum, values: ["backlog", "todo", "doing", "done"], description: "Move the ticket"
    field :priority, :enum, values: ["low", "med", "high"]
    field :title, :string
    field :body, :string
    field :assignee, :string
  end

  @impl true
  def execute(params, frame) do
    case Tickets.get(params[:id]) do
      nil ->
        fail(frame, "no ticket ##{params[:id]}")

      ticket ->
        attrs = params |> Map.delete(:id) |> Map.reject(fn {_k, v} -> is_nil(v) end)
        reply(frame, Tickets.update(ticket, attrs), &MCP.Brief.ticket/1)
    end
  end
end

defmodule Server.MCP.Tool.WriteNote do
  @moduledoc """
  Write a NOTE — funes-native scratch, agent-readable/writable. Defaults to a note on THIS thread;
  pass `scope: "global" | "workspace" | "project"` (with `scope_id`, or none for global) to place
  it elsewhere. A `workspace`/`project` scope with no `scope_id` uses the bound thread's own.
  """
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.MCP.Tool
  alias Server.Notes

  schema do
    field :body, :string, required: true, description: "The note (markdown)"
    field :scope, :enum, values: ["global", "workspace", "project", "thread"], default: "thread"
    field :scope_id, :integer, description: "Target id; defaults to the bound thread/workspace/project"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    scope = params[:scope]
    scope_id = resolve_scope_id(scope, params[:scope_id], identity)

    %{body: params[:body], scope: scope, scope_id: scope_id, author: identity.agent}
    |> Notes.write()
    |> then(&reply(frame, &1, fn note -> MCP.Brief.note(note) end))
  end

  defp resolve_scope_id("global", _given, _identity), do: nil
  defp resolve_scope_id("thread", nil, identity), do: identity.thread_id
  defp resolve_scope_id("workspace", nil, identity), do: Tool.workspace_of(identity)
  defp resolve_scope_id(_scope, given, _identity), do: given
end

defmodule Server.MCP.Tool.GetNotes do
  @moduledoc "Read notes in a scope — defaults to THIS thread's notes. Pass `scope`/`scope_id` for elsewhere."
  use Server.MCP.Tool

  alias Server.MCP
  alias Server.MCP.Tool
  alias Server.Notes

  schema do
    field :scope, :enum, values: ["global", "workspace", "project", "thread"], default: "thread"
    field :scope_id, :integer, description: "Target id; defaults to the bound thread/workspace"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    scope = params[:scope]

    scope_id =
      case {scope, params[:scope_id]} do
        {"global", _} -> nil
        {"thread", nil} -> identity.thread_id
        {"workspace", nil} -> Tool.workspace_of(identity)
        {_, given} -> given
      end

    ok(frame, Enum.map(Notes.for_scope(scope, scope_id), &MCP.Brief.note/1))
  end
end
