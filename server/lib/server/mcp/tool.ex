defmodule Server.MCP.Tool do
  @moduledoc """
  The tool surface's one seam (pi doc §2a/§5.1): every tool is a thin caller of a context, never
  a second writer (§10), and identity (thread, agent, session) rides the connection via
  `Server.MCP.Identity`, so no self-thread tool takes a thread parameter — misdirection is
  unrepresentable. `use Server.MCP.Tool` makes a module an anubis tool component and imports the
  reply helpers below; the tools themselves live in `lib/server/mcp/tools/<family>.ex`.
  """
  alias Anubis.Server.Frame
  alias Anubis.Server.Response

  defmacro __using__(_opts) do
    quote do
      use Anubis.Server.Component, type: :tool

      import Server.MCP.Tool, only: [ok: 2, fail: 2, reply: 3, own: 4]

      alias Server.MCP.Identity, warn: false
    end
  end

  @typedoc "What a tool's `execute/2` returns."
  @type tool_reply :: {:reply, Response.t(), Frame.t()}

  @doc "A successful tool reply carrying `payload` as JSON."
  @spec ok(Frame.t(), term()) :: tool_reply()
  def ok(frame, payload), do: {:reply, Response.json(Response.tool(), payload), frame}

  @doc "A tool-error reply with `message`."
  @spec fail(Frame.t(), String.t()) :: tool_reply()
  def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

  @doc """
  Reply from a context result: `{:ok, row}` renders `render.(row)`; a changeset error becomes
  one sentence (`changeset_error/1`); a string reason is the message verbatim. Any other reason
  is the tool's to word — map it before calling.
  """
  @spec reply(Frame.t(), {:ok, term()} | {:error, Ecto.Changeset.t() | String.t()}, (term() -> term())) ::
          tool_reply()
  def reply(frame, {:ok, row}, render), do: ok(frame, render.(row))
  def reply(frame, {:error, %Ecto.Changeset{} = changeset}, _render), do: fail(frame, changeset_error(changeset))
  def reply(frame, {:error, reason}, _render) when is_binary(reason), do: fail(frame, reason)

  @doc """
  Act on a row that must belong to THIS connection's thread — the identity scoping every
  by-id tool rests on. `{noun, id, row}`: a nil row is "no such <noun>: <id>", another thread's
  row is refused, and only an own row reaches `fun`.
  """
  @spec own(Frame.t(), integer(), {String.t(), term(), struct() | nil}, (struct() -> tool_reply())) :: tool_reply()
  def own(frame, _thread_id, {noun, id, nil}, _fun), do: fail(frame, "no such #{noun}: #{id}")
  def own(_frame, thread_id, {_noun, _id, %{thread_id: thread_id} = row}, fun), do: fun.(row)
  def own(frame, _thread_id, {noun, _id, _row}, _fun), do: fail(frame, "that #{noun} is on another thread")

  @doc """
  The `workspace_id` of the connection's bound thread — the "current workspace" the
  workspace-scoped container tools (tickets/notes/projects) write into, since identity
  carries a thread, not a workspace. `nil` if the thread is gone.
  """
  def workspace_of(%{thread_id: thread_id}) do
    case Server.Repo.get(Server.Thread, thread_id) do
      %Server.Thread{workspace_id: wid} -> wid
      _ -> nil
    end
  end

  @doc "A changeset's errors as one tool-error sentence."
  def changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end

defmodule Server.MCP.Tool.OpenThread do
  @moduledoc """
  Open a NEW thread — a fresh unit of work. One of the two DELIBERATE cross-thread verbs:
  unlike every other tool, it does not act on the connection's own thread (there is no
  thread to misdirect — it is creating one). An orchestrator opens threads for work to be
  picked up; the returned id is how a pane is then spawned onto it (`Server.MCP.Spawn`).
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP

  schema do
    field :title, :string, required: true, description: "What the thread is for (its NORTH STAR)"
  end

  @impl true
  def execute(params, frame) do
    case Channel.open_thread(%{title: params[:title]}) do
      {:ok, thread} ->
        {:reply, Response.json(Response.tool(), %{"thread_id" => thread.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.StaffChild do
  @moduledoc """
  Open a NEW worker-led CHILD thread — the sanctioned "delegate a sub-effort" verb (lead-as-manager,
  Slice 4D). Composes the cross-thread primitives: open a thread titled `title` parented at the
  CALLER's thread (so its close reports up) and inheriting the caller's project, assign the registered
  agent `lead`, and post `brief` (authored by the caller's bound identity) as its opening message.
  Staffing, not spawning: no terminal starts here — the cockpit's convergent sweep sees a worker-led
  thread without a window and stands one up (human-named, `@funes_thread`-tagged, cap-accounted, its
  harness server-bound). An agent never launches a harness by hand — a bare spawn is not a server
  citizen and is invisible to the board; it staffs the thread and lets the board actuate.

  The lead resolves BEFORE the thread opens, so a bad handle refuses cleanly instead of leaving an
  orphan lead-less thread — the machine-chat silence bug's tool-side twin.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Agent
  alias Server.Channel
  alias Server.MCP
  alias Server.Staff

  schema do
    field :title, :string, required: true, description: "What the child thread is for (its NORTH STAR)"
    field :lead, :string, required: true, description: "Registered worker handle to staff as lead (e.g. hronir-machine)"
    field :brief, :string, required: true, description: "The opening assignment, posted as the thread's first message"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    # The child is parented at the CALLER's bound thread (lead-as-manager, Slice 4D) so its close
    # reports up, and inherits the caller's project. An unbound caller opens a top-level thread.
    parent = identity.thread_id && Channel.thread(identity.thread_id)

    with {:agent, %Agent{}} <- {:agent, Staff.agent_by_name(params[:lead])},
         {:ok, thread} <- Channel.open_thread(child_attrs(params[:title], parent)),
         {:ok, _} <- Channel.assign_lead(thread.id, params[:lead]),
         {:ok, _} <- Channel.post(%{thread_id: thread.id, author: identity.agent, body: params[:brief]}) do
      {:reply, Response.json(Response.tool(), %{"thread_id" => thread.id, "lead" => params[:lead]}), frame}
    else
      {:agent, nil} ->
        {:reply,
         Response.error(
           Response.tool(),
           "no registered agent named #{inspect(params[:lead])} — staff a handle from the workspace roster"
         ), frame}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "staff_child failed: #{inspect(reason)}"), frame}
    end
  end

  defp child_attrs(title, nil), do: %{title: title}
  defp child_attrs(title, parent), do: %{title: title, parent_thread_id: parent.id, project_id: parent.project_id}
end

defmodule Server.MCP.Tool.CloseThread do
  @moduledoc """
  Close a thread by id — the second DELIBERATE cross-thread verb. History outlives the
  close (messages are untouched); a closed thread just leaves the open list. It takes a
  thread id BY DESIGN — closing a peer's finished thread is the coordination act this verb
  exists for, the sanctioned exception to "no tool takes a thread parameter". A missing id
  is refused.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel

  schema do
    field :thread_id, :integer, required: true, description: "The thread to close"
  end

  @impl true
  def execute(params, frame) do
    case Channel.thread(params[:thread_id]) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such thread: #{params[:thread_id]}"), frame}

      thread ->
        {:ok, closed} = Channel.close_thread(thread)
        {:reply, Response.json(Response.tool(), %{"closed" => closed.id, "state" => closed.state}), frame}
    end
  end
end

defmodule Server.MCP.Tool.AssignLead do
  @moduledoc """
  (Re)assign a thread's LEAD by id — the orchestrator's staffing verb (lead-as-manager, Slice 4D).
  tertius routes an intent by opening a thread then assigning who leads; a lead reassigns when a
  different coworker fits. Takes a thread_id BY DESIGN — like close_thread, staffing a thread other
  than the caller's own is exactly the coordination act this verb exists for. A missing thread or an
  unregistered handle refuses cleanly, never leaving a half-staffed thread.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel

  schema do
    field :thread_id, :integer, required: true, description: "The thread to staff"
    field :lead, :string, required: true, description: "Registered worker handle to assign as lead (e.g. hronir-machine)"
  end

  @impl true
  def execute(params, frame) do
    case Channel.assign_lead(params[:thread_id], params[:lead]) do
      {:ok, _thread} ->
        {:reply, Response.json(Response.tool(), %{"thread_id" => params[:thread_id], "lead" => params[:lead]}), frame}

      {:error, :no_agent} ->
        {:reply, Response.error(Response.tool(), "no registered agent named #{inspect(params[:lead])}"), frame}

      {:error, :no_thread} ->
        {:reply, Response.error(Response.tool(), "no such thread: #{params[:thread_id]}"), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "assign_lead failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.SwitchThread do
  @moduledoc """
  Move THIS connection onto another thread — the coordination act behind episode ROTATION. Mints a
  fresh token bound to `{thread_id, this agent}` and returns it; the adapter re-handshakes with it,
  so the agent's WARM session is untouched (its LLM cache stays) — only WHERE its posts land moves.
  The fourth deliberate cross-thread verb (after open/close_thread, consult_peer): it takes a thread
  id BY DESIGN. A missing thread (or agent) is refused — never mint against a guess.

  Minting here grants no access on its own — the same as `/mint` (127.0.0.1-only): the bearer still
  has to re-connect and `register`. So this is the SIGNAL half of the switch; the adapter that holds
  the connection performs the re-handshake with the returned token.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP.Identity
  alias Server.MCP.Spawn

  schema do
    field :thread_id, :integer, required: true, description: "The thread to move this connection onto"
  end

  @impl true
  def execute(params, frame) do
    agent = Identity.from_frame(frame).agent

    case Spawn.mint_for(params[:thread_id], agent) do
      {:ok, token} ->
        {:reply, Response.json(Response.tool(), %{"thread_id" => params[:thread_id], "token" => token}), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "cannot switch to thread #{params[:thread_id]}: #{inspect(reason)}"),
         frame}
    end
  end
end

defmodule Server.MCP.Tool.ConsultPeer do
  @moduledoc """
  Ask a peer agent a question — the third DELIBERATE cross-thread verb (after
  open_thread/close_thread). The caller names a peer AGENT, never a thread id; server
  resolves the peer's target thread (agent-filtered, with a defined tie-break) and
  delivers the ask there. The peer's answer is mirrored back to the caller's own thread
  (see `Server.Consult`), so the caller reads it in its own dossier. A missing or
  ambiguous peer is refused.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Consult
  alias Server.MCP

  schema do
    field :peer, :string, required: true, description: "The peer agent's name to ask"
    field :prompt, :string, required: true, description: "The question to ask the peer"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Consult.consult_peer(identity, params[:peer], params[:prompt]) do
      {:ok, %{consult_id: consult_id, peer_thread_id: peer_thread_id}} ->
        {:reply,
         Response.json(Response.tool(), %{
           "consult_id" => consult_id,
           "peer_thread_id" => peer_thread_id
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "consult_peer failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.SpawnCrew do
  @moduledoc """
  Staff a crew role onto THIS thread — the lead's spawn verb (server crew MVP). Mints the role's
  server identity on your thread and stands up its terminal, then hands it `task` as its opening
  assignment. MVP role is `reviewer`. Like every self-thread tool it takes no thread parameter: the
  role joins the connection's own thread, so a lead spawns a reviewer onto the work it is leading.

  Actuated by the configured crew backend (`Server.Crew`) — on the console hub that spawns the window
  in the live node. With no backend (the standalone service) it reports unavailable rather than
  faking a spawn.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Crew
  alias Server.MCP

  schema do
    field :task, :string, required: true, description: "The opening assignment — what the role should do"
    field :role, :string, description: "Crew role to staff (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.spawn_role(role, identity.thread_id, params[:task]) do
      {:ok, window} ->
        payload = %{"role" => role, "thread_id" => identity.thread_id, "window" => to_string(window)}
        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, :no_crew} ->
        {:reply, Response.error(Response.tool(), "crew spawning is unavailable here — no crew backend is configured"),
         frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "crew spawn failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.KillCrew do
  @moduledoc """
  Tear down a crew role's terminal on THIS thread — the lead's teardown verb (server crew MVP).
  Thread-scoped by the connection's identity; role defaults to `reviewer`. Best-effort: a role that
  is already gone is not an error.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Crew
  alias Server.MCP

  schema do
    field :role, :string, description: "Crew role to tear down (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.kill_role(role, identity.thread_id) do
      :ok ->
        {:reply, Response.json(Response.tool(), %{"killed" => role, "thread_id" => identity.thread_id}), frame}

      {:error, :no_crew} ->
        {:reply, Response.error(Response.tool(), "crew teardown is unavailable here — no crew backend is configured"),
         frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "crew kill failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.RegisterWorkspace do
  @moduledoc """
  Register a WORKSPACE — a first-class composition (workspaces/orbis Slice 1): a git-tracked
  scope (`paths`), a `roster` of archetype instances, and free-form `knobs` that console
  reads to drive its picker/survey/spawn. Unlike the thread-scoped tools this is
  machine-GLOBAL — it takes no identity, it writes the shared `workspace` table via
  `Server.Workspaces`. `name` is unique; a duplicate is a graceful error, not a crash.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
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
    case Workspaces.register(params) do
      {:ok, workspace} ->
        {:reply, Response.json(Response.tool(), %{"workspace_id" => workspace.id, "name" => workspace.name}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.ListWorkspaces do
  @moduledoc """
  Every WORKSPACE, newest-first — the machine-global read console's Orbis survey/picker maps
  over. Takes no identity: workspaces are not thread-scoped.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Workspaces

  schema do
  end

  @impl true
  def execute(_params, frame) do
    workspaces = Enum.map(Workspaces.all(), &MCP.Brief.workspace/1)
    {:reply, Response.json(Response.tool(), workspaces), frame}
  end
end

defmodule Server.MCP.Tool.EditWorkspace do
  @moduledoc """
  Edit a WORKSPACE's mutable fields (`type`/`scope`/`paths`/`roster`/`knobs`), identified by
  its unique `name` — a workspace's identity is immutable, so name is the handle, not a
  field this rewrites. Machine-global; a missing workspace is refused rather than created.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
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
      nil ->
        {:reply, Response.error(Response.tool(), "no such workspace: #{params[:name]}"), frame}

      workspace ->
        case Workspaces.edit(workspace, params) do
          {:ok, edited} ->
            {:reply, Response.json(Response.tool(), MCP.Brief.workspace(edited)), frame}

          {:error, changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.RemoveWorkspace do
  @moduledoc """
  Remove a WORKSPACE by its unique `name` — machine-global, thread-independent. A missing
  workspace is refused rather than reported as removed.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace to remove (its unique name)"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.by_name(params[:name]) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such workspace: #{params[:name]}"), frame}

      workspace ->
        case Workspaces.remove(workspace) do
          {:ok, removed} ->
            {:reply, Response.json(Response.tool(), %{"removed" => removed.name}), frame}

          {:error, :last_workspace} ->
            {:reply,
             Response.error(
               Response.tool(),
               "refused: #{workspace.name} is the last workspace — threads must have a home"
             ), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.TrackThread do
  @moduledoc """
  Promote THIS connection's thread into the stage machine at "build" — tracking is
  the lazy path (reshape slice B): the harness hooks call this mechanically on the
  first successful `git commit`, so the ticket condenses out of the work. Agents may
  also call it deliberately ("track this thread"). Idempotent; self-thread like every
  write — no thread parameter exists to misdirect.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Repo.get(Thread, identity.thread_id) do
      nil ->
        {:reply, Response.error(Response.tool(), "no thread ##{identity.thread_id}"), frame}

      thread ->
        case Workline.promote(thread) do
          {:ok, tracked} ->
            payload = %{"stage" => tracked.stage, "slug" => tracked.slug}
            {:reply, Response.json(Response.tool(), payload), frame}

          {:error, :root_machine_thread} ->
            {:reply, Response.error(Response.tool(), "refused: the root machine thread is not a work item"), frame}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.AdvanceStage do
  @moduledoc """
  Advance THIS thread's workline past its current stage (worklines slice 1) — the single
  sanctioned mutation. Refused without the stage's owed artifact COMMITTED (the check lands
  in CHECKS either way); gated transitions (spec→plan, review→merged, machine-born intent)
  park `awaiting: andrew` — the operator approves, an agent never can. Identity-bound: no
  thread parameter, you advance the workline you are standing on.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP.Identity
  alias Server.Workline

  schema do
  end

  @impl true
  def execute(_params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    case Channel.thread(thread_id) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such thread: #{thread_id}"), frame}

      thread ->
        reply(Workline.advance(thread), frame)
    end
  end

  defp reply({:ok, thread}, frame),
    do: {:reply, Response.json(Response.tool(), %{"stage" => thread.stage, "awaiting" => thread.awaiting}), frame}

  defp reply({:awaiting, thread}, frame),
    do:
      {:reply,
       Response.json(Response.tool(), %{
         "stage" => thread.stage,
         "awaiting" => thread.awaiting,
         "note" => "gated — the operator approves this transition"
       }), frame}

  defp reply({:error, {:artifact_missing, why}}, frame),
    do: {:reply, Response.error(Response.tool(), "owed artifact missing: #{why}"), frame}

  defp reply({:error, reason}, frame),
    do: {:reply, Response.error(Response.tool(), "cannot advance: #{inspect(reason)}"), frame}
end

defmodule Server.MCP.Tool.SubmitReview do
  @moduledoc """
  The write-fenced reviewer's ONE door (worklines slice 3): server writes and commits
  work/<slug>/review.md itself — the reviewer profile structurally cannot (write/edit
  denied). Identity-bound to THIS thread, refused outside the review stage. Verdict at
  the top of the body; then call advance_stage to hand the merge gate to the operator.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP.Identity
  alias Server.Workline.Review

  schema do
    field :body, :string, required: true, description: "The full review.md content — verdict first, then findings"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{} = thread <- Channel.thread(identity.thread_id) || {:error, :no_thread},
         {:ok, rel} <- Review.submit(thread, params[:body], identity.agent) do
      {:reply, Response.json(Response.tool(), %{"committed" => rel}), frame}
    else
      {:error, {:not_in_review, stage}} ->
        {:reply, Response.error(Response.tool(), "not in review — this workline is at #{stage}"), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "submit_review failed: #{inspect(reason)}"), frame}
    end
  end
end
