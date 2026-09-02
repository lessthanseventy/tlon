defmodule Server.MCP.Tool.Containers do
  @moduledoc """
  Container-tier MCP tools (2026-08-30): the agent-facing surface over `Server.Tickets`,
  `Server.Notes`, and `Server.Projects`. Like `register_workspace` these are workspace-scoped
  rather than thread-scoped — but identity carries a thread, so the "current workspace" is
  resolved from the bound thread (`Server.MCP.Tool.workspace_of/1`). Each is a thin caller of
  its context, never a second writer (§10). Grouped here as several small faces, the way
  `Server.MCP.Tool` groups the slice-1 tools.
  """

  defp ticket_json(t) do
    %{
      "id" => t.id,
      "title" => t.title,
      "status" => t.status,
      "priority" => t.priority,
      "labels" => t.labels,
      "assignee" => t.assignee,
      "promoted_thread_id" => t.promoted_thread_id
    }
  end

  defp note_json(n),
    do: %{"id" => n.id, "scope" => n.scope, "scope_id" => n.scope_id, "body" => n.body, "author" => n.author}

  def ticket_json_public(t), do: ticket_json(t)
  def note_json_public(n), do: note_json(n)
end

defmodule Server.MCP.Tool.FileTicket do
  @moduledoc """
  File a TICKET into the current workspace's lightweight tracker — the 2-second capture ("this
  is fucked, file it") that does NOT spin up a thread. Workspace-scoped (resolved from the bound
  thread). Lands at `backlog`; promote it into a thread later when work starts.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.MCP.Tool.Containers
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
    identity = MCP.Identity.from_frame(frame)

    case MCP.Tool.workspace_of(identity) do
      nil ->
        {:reply, Response.error(Response.tool(), "no workspace bound to this session"), frame}

      workspace_id ->
        case Tickets.file(Map.put(params, :workspace_id, workspace_id)) do
          {:ok, ticket} ->
            {:reply, Response.json(Response.tool(), Containers.ticket_json_public(ticket)), frame}

          {:error, changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.ListTickets do
  @moduledoc "Open tickets in the current workspace's tracker (newest-first), the board reads. Workspace-scoped via the bound thread."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.MCP.Tool.Containers
  alias Server.Tickets

  schema do
    field :include_done, :boolean, default: false, description: "Include done tickets (default: only open)"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case MCP.Tool.workspace_of(identity) do
      nil ->
        {:reply, Response.error(Response.tool(), "no workspace bound to this session"), frame}

      workspace_id ->
        tickets =
          if params[:include_done],
            do: Tickets.in_workspace(workspace_id),
            else: Tickets.open_in_workspace(workspace_id)

        {:reply, Response.json(Response.tool(), Enum.map(tickets, &Containers.ticket_json_public/1)), frame}
    end
  end
end

defmodule Server.MCP.Tool.UpdateTicket do
  @moduledoc "Update a ticket's status/priority/title/body/assignee. `id` identifies it; a missing ticket is refused."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.MCP.Tool.Containers
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
        {:reply, Response.error(Response.tool(), "no ticket ##{params[:id]}"), frame}

      ticket ->
        attrs = params |> Map.delete(:id) |> Map.reject(fn {_k, v} -> is_nil(v) end)

        case Tickets.update(ticket, attrs) do
          {:ok, updated} -> {:reply, Response.json(Response.tool(), Containers.ticket_json_public(updated)), frame}
          {:error, changeset} -> {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.WriteNote do
  @moduledoc """
  Write a NOTE — funes-native scratch, agent-readable/writable. Defaults to a note on THIS thread;
  pass `scope: "global" | "workspace" | "project"` (with `scope_id`, or none for global) to place
  it elsewhere. A `workspace`/`project` scope with no `scope_id` uses the bound thread's own.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.MCP.Tool.Containers
  alias Server.Notes

  schema do
    field :body, :string, required: true, description: "The note (markdown)"
    field :scope, :enum, values: ["global", "workspace", "project", "thread"], default: "thread"
    field :scope_id, :integer, description: "Target id; defaults to the bound thread/workspace/project"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    scope = params[:scope]
    scope_id = resolve_scope_id(scope, params[:scope_id], identity)

    case Notes.write(%{body: params[:body], scope: scope, scope_id: scope_id, author: identity.agent}) do
      {:ok, note} -> {:reply, Response.json(Response.tool(), Containers.note_json_public(note)), frame}
      {:error, changeset} -> {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end

  defp resolve_scope_id("global", _given, _identity), do: nil
  defp resolve_scope_id("thread", nil, identity), do: identity.thread_id
  defp resolve_scope_id("workspace", nil, identity), do: MCP.Tool.workspace_of(identity)
  defp resolve_scope_id(_scope, given, _identity), do: given
end

defmodule Server.MCP.Tool.GetNotes do
  @moduledoc "Read notes in a scope — defaults to THIS thread's notes. Pass `scope`/`scope_id` for elsewhere."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.MCP.Tool.Containers
  alias Server.Notes

  schema do
    field :scope, :enum, values: ["global", "workspace", "project", "thread"], default: "thread"
    field :scope_id, :integer, description: "Target id; defaults to the bound thread/workspace"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    scope = params[:scope]

    scope_id =
      case {scope, params[:scope_id]} do
        {"global", _} -> nil
        {"thread", nil} -> identity.thread_id
        {"workspace", nil} -> MCP.Tool.workspace_of(identity)
        {_, given} -> given
      end

    notes = Notes.for_scope(scope, scope_id)
    {:reply, Response.json(Response.tool(), Enum.map(notes, &Containers.note_json_public/1)), frame}
  end
end

defmodule Server.MCP.Tool.RegisterProject do
  @moduledoc """
  Register a PROJECT in the current workspace (the middle tier: Workspace ▸ Project ▸ Thread) —
  a named effort spanning one or more repos. Workspace-scoped via the bound thread; `name` is
  unique within the workspace.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Projects

  schema do
    field :name, :string, required: true, description: "The project's name (unique in the workspace)"
    field :repos, {:list, :map}, default: [], description: "Repos: {name, path, url?}"
    field :knobs, :map, default: %{}, description: "Free-form per-project settings"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case MCP.Tool.workspace_of(identity) do
      nil ->
        {:reply, Response.error(Response.tool(), "no workspace bound to this session"), frame}

      workspace_id ->
        case Projects.register(Map.put(params, :workspace_id, workspace_id)) do
          {:ok, project} ->
            {:reply, Response.json(Response.tool(), %{"project_id" => project.id, "name" => project.name}), frame}

          {:error, changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end
