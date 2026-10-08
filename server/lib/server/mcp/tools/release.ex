defmodule Server.MCP.Tool.ReleaseStatus do
  @moduledoc """
  The PM's view of the release (pm-and-release design §4): what runs (`live`), origin/main, the
  commits on main not yet released, and the mechanical checks on main's tip — the gate and the smoke
  on exactly that commit, and nothing mid-flight (`Server.Release.Candidate`).
  """
  use Server.MCP.Tool

  alias Server.Release.PM

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case PM.status() do
      {:ok, s} ->
        ok(frame, %{
          "live" => s.live,
          "main" => s.main,
          "waiting" => Enum.map(s.waiting, &%{"sha" => String.slice(&1.sha, 0, 7), "subject" => &1.subject}),
          "checks" => s.checks
        })

      {:error, why} ->
        fail(frame, why)
    end
  end
end

defmodule Server.MCP.Tool.ProposeRelease do
  @moduledoc """
  Propose a release (`Server.Release.PM.propose/4`): refused unless the commit is on main, ahead of
  live and releasable. Then graded off the request path: if every change fits the operator's standing
  approval the server cuts it, else it reaches them as one gate (approve / not yet). Either outcome
  posts to the workspace's root thread.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool
  alias Server.Release.PM

  schema do
    field :sha, :string, description: "The commit on main to release (default: origin/main's tip)"

    field :changelog, :string,
      description:
        "What shipped to the operator, in their words: what they can now do or will notice — not commit subjects"
  end

  @impl true
  def execute(params, frame) do
    case Tool.workspace_of(Identity.from_frame(frame)) do
      nil ->
        fail(frame, "no workspace bound to this session")

      ws ->
        case PM.propose(ws, params[:sha], params[:changelog]) do
          {:ok, %{sha: sha, changes: n}} ->
            ok(frame, %{
              "proposed" => sha,
              "changes" => n,
              "next" => "grading it now; the cut or the gate for the operator posts to the root thread"
            })

          {:error, why} ->
            fail(frame, why)
        end
    end
  end
end

defmodule Server.MCP.Tool.SetUrgency do
  @moduledoc """
  Set a backlog ticket's urgency — its priority, which `Server.Intake` starts the most urgent
  unblocked ticket by — and say on the workspace's root thread what's next and why, as a notice
  that wakes nobody. A ticket outside the caller's workspace is refused.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool
  alias Server.Ticket
  alias Server.Tickets

  schema do
    field :ticket_id, :integer, required: true, description: "The ticket"
    field :priority, :enum, values: ["low", "med", "high"], required: true
    field :why, :string, required: true, description: "One line: why it moves"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    ws = Tool.workspace_of(identity)

    with %Ticket{workspace_id: ^ws} = ticket <- Tickets.get(params[:ticket_id]),
         {:ok, moved} <- Tickets.update(ticket, %{priority: params[:priority]}) do
      if moved.priority != ticket.priority, do: tell(ws, identity.agent, moved, params[:why])
      ok(frame, Server.MCP.Brief.ticket(moved))
    else
      {:error, _} = error -> reply(frame, error, & &1)
      _ -> fail(frame, "no ticket ##{params[:ticket_id]} in this workspace")
    end
  end

  defp tell(ws, author, ticket, why) do
    next =
      case Server.Intake.next(ws) do
        nil -> "the backlog is empty"
        t -> "next up: ##{t.id} #{t.title}"
      end

    with %Server.Thread{id: root} <- Server.Channel.machine_thread(ws) do
      Server.Channel.post(%{
        thread_id: root,
        author: author,
        kind: "notice",
        body: "📋 ##{ticket.id} #{ticket.title} → #{ticket.priority}: #{why}. #{next}"
      })
    end
  end
end
