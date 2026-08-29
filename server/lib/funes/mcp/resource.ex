defmodule Server.MCP.Resource.Brief do
  @moduledoc """
  The connection's thread brief as a readable resource — the SAME read as the
  get_brief tool (`Board.brief/1` through `Server.MCP.Brief`): one source,
  two protocol doors. The tool is for the model mid-turn; the resource is for a
  host briefing a session (pi's before_agent_start pulls this).
  """
  use Anubis.Server.Component,
    type: :resource,
    uri: "tlon://brief",
    mime_type: "application/json"

  alias Anubis.Server.Response
  alias Server.Board
  alias Server.MCP
  alias Server.Thread

  @impl true
  def read(_params, frame) do
    identity = MCP.Identity.from_frame(frame)
    brief = %Thread{id: identity.thread_id} |> Board.brief() |> MCP.Brief.scope()
    {:reply, Response.json(Response.resource(), brief), frame}
  end
end

defmodule Server.MCP.Resource.Constraints do
  @moduledoc """
  The always-loaded constraint set (§4): the operator's stated, unsuperseded
  constraints — the rows every session reads at start, machine-wide. Served to
  ANY agent over the channel, which is what makes the constraint set
  agent-agnostic rather than a pi feature.
  """
  use Anubis.Server.Component,
    type: :resource,
    uri: "tlon://constraints",
    mime_type: "application/json"

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  @impl true
  def read(_params, frame) do
    constraints = Enum.map(Dossier.always_loaded_constraints(), &MCP.Brief.fact/1)
    {:reply, Response.json(Response.resource(), constraints), frame}
  end
end

defmodule Server.MCP.Resource.Habits do
  @moduledoc """
  The always-loaded approved habits (roadmap: pi-synthesis slice 2): the operator-approved
  "how to work with Andrew" preferences every session reads at start, machine-wide, beside
  the constraints. Mirrors `Resource.Constraints` but for a different provenance — a habit is
  agent-PROPOSED (`propose_habit`) and human-APPROVED, whereas a constraint is his verbatim
  words. Served to ANY agent over the channel, which is what keeps the set agent-agnostic.
  """
  use Anubis.Server.Component,
    type: :resource,
    uri: "tlon://habits",
    mime_type: "application/json"

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  @impl true
  def read(_params, frame) do
    habits = Enum.map(Dossier.approved_habits(), &MCP.Brief.habit/1)
    {:reply, Response.json(Response.resource(), habits), frame}
  end
end
