defmodule Server.MCP.Tool.OpenThread do
  @moduledoc """
  Open a NEW thread — a fresh unit of work. One of the two DELIBERATE cross-thread verbs:
  unlike every other tool, it does not act on the connection's own thread (there is no
  thread to misdirect — it is creating one). An orchestrator opens threads for work to be
  picked up; the returned id is how a pane is then spawned onto it (`Server.MCP.Spawn`).
  """
  use Server.MCP.Tool

  alias Server.Channel

  schema do
    field :title, :string, required: true, description: "What the thread is for (its NORTH STAR)"
  end

  @impl true
  def execute(params, frame) do
    reply(frame, Channel.open_thread(%{title: params[:title]}), fn thread -> %{"thread_id" => thread.id} end)
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
  use Server.MCP.Tool

  alias Server.Agent
  alias Server.Channel
  alias Server.Staff

  schema do
    field :title, :string, required: true, description: "What the child thread is for (its NORTH STAR)"
    field :lead, :string, required: true, description: "Registered worker handle to staff as lead (e.g. hronir-machine)"
    field :brief, :string, required: true, description: "The opening assignment, posted as the thread's first message"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    # The child is parented at the CALLER's bound thread (lead-as-manager, Slice 4D) so its close
    # reports up, and inherits the caller's project. An unbound caller opens a top-level thread.
    parent = identity.thread_id && Channel.thread(identity.thread_id)

    with {:agent, %Agent{}} <- {:agent, Staff.agent_by_name(params[:lead])},
         {:ok, thread} <- Channel.open_thread(child_attrs(params[:title], parent)),
         {:ok, _} <- Channel.assign_lead(thread.id, params[:lead]),
         {:ok, _} <- Channel.post(%{thread_id: thread.id, author: identity.agent, body: params[:brief]}) do
      ok(frame, %{"thread_id" => thread.id, "lead" => params[:lead]})
    else
      {:agent, nil} ->
        fail(frame, "no registered agent named #{inspect(params[:lead])} — staff a handle from the workspace roster")

      {:error, %Ecto.Changeset{}} = error ->
        reply(frame, error, & &1)

      {:error, reason} ->
        fail(frame, "staff_child failed: #{inspect(reason)}")
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
  use Server.MCP.Tool

  alias Server.Channel

  schema do
    field :thread_id, :integer, required: true, description: "The thread to close"
  end

  @impl true
  def execute(params, frame) do
    case Channel.thread(params[:thread_id]) do
      nil ->
        fail(frame, "no such thread: #{params[:thread_id]}")

      thread ->
        {:ok, closed} = Channel.close_thread(thread)
        ok(frame, %{"closed" => closed.id, "state" => closed.state})
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
  use Server.MCP.Tool

  alias Server.Channel

  schema do
    field :thread_id, :integer, required: true, description: "The thread to staff"

    field :lead, :string,
      required: true,
      description: "Registered worker handle to assign as lead (e.g. hronir-machine)"
  end

  @impl true
  def execute(params, frame) do
    case Channel.assign_lead(params[:thread_id], params[:lead]) do
      {:ok, _thread} -> ok(frame, %{"thread_id" => params[:thread_id], "lead" => params[:lead]})
      {:error, :no_agent} -> fail(frame, "no registered agent named #{inspect(params[:lead])}")
      {:error, :no_thread} -> fail(frame, "no such thread: #{params[:thread_id]}")
      {:error, reason} -> fail(frame, "assign_lead failed: #{inspect(reason)}")
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
  use Server.MCP.Tool

  alias Server.MCP.Spawn

  schema do
    field :thread_id, :integer, required: true, description: "The thread to move this connection onto"
  end

  @impl true
  def execute(params, frame) do
    agent = Identity.from_frame(frame).agent

    case Spawn.mint_for(params[:thread_id], agent) do
      {:ok, token} -> ok(frame, %{"thread_id" => params[:thread_id], "token" => token})
      {:error, reason} -> fail(frame, "cannot switch to thread #{params[:thread_id]}: #{inspect(reason)}")
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
  use Server.MCP.Tool

  alias Server.Consult

  schema do
    field :peer, :string, required: true, description: "The peer agent's name to ask"
    field :prompt, :string, required: true, description: "The question to ask the peer"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    case Consult.consult_peer(identity, params[:peer], params[:prompt]) do
      {:ok, %{consult_id: consult_id, peer_thread_id: peer_thread_id}} ->
        ok(frame, %{"consult_id" => consult_id, "peer_thread_id" => peer_thread_id})

      {:error, reason} ->
        fail(frame, "consult_peer failed: #{inspect(reason)}")
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
  use Server.MCP.Tool

  alias Server.Crew

  schema do
    field :task, :string, required: true, description: "The opening assignment — what the role should do"
    field :role, :string, description: "Crew role to staff (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.spawn_role(role, identity.thread_id, params[:task]) do
      {:ok, window} ->
        ok(frame, %{"role" => role, "thread_id" => identity.thread_id, "window" => to_string(window)})

      {:error, :no_crew} ->
        fail(frame, "crew spawning is unavailable here — no crew backend is configured")

      {:error, reason} ->
        fail(frame, "crew spawn failed: #{inspect(reason)}")
    end
  end
end

defmodule Server.MCP.Tool.KillCrew do
  @moduledoc """
  Tear down a crew role's terminal on THIS thread — the lead's teardown verb (server crew MVP).
  Thread-scoped by the connection's identity; role defaults to `reviewer`. Best-effort: a role that
  is already gone is not an error.
  """
  use Server.MCP.Tool

  alias Server.Crew

  schema do
    field :role, :string, description: "Crew role to tear down (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.kill_role(role, identity.thread_id) do
      :ok -> ok(frame, %{"killed" => role, "thread_id" => identity.thread_id})
      {:error, :no_crew} -> fail(frame, "crew teardown is unavailable here — no crew backend is configured")
      {:error, reason} -> fail(frame, "crew kill failed: #{inspect(reason)}")
    end
  end
end
