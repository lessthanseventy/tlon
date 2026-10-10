defmodule Server.MCP.Tool.TakeWakes do
  @moduledoc """
  The wakes queued for this session's pane (`Server.Wake`), oldest first, taken: the tlon-citizen
  mod drains them on a short timer and submits each as a turn once the session is idle. Taking is
  not activity — the identity is read without touching warmth — so a session that only drains
  stays as cold as it is, and only the turn a wake starts counts as having heard it.
  """
  use Server.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame, touch: false)
    ok(frame, Server.Wake.take(identity.thread_id, identity.agent))
  end
end

defmodule Server.MCP.Tool.PutBackWakes do
  @moduledoc """
  Wakes this session took (`take_wakes`) but could not submit, queued again for the same thread
  and agent so the next take hands them over. Like taking, putting back is not activity.
  """
  use Server.MCP.Tool

  schema do
    field :prompts, {:list, :string}, required: true, description: "The wakes' prompts, as take_wakes returned them"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame, touch: false)
    {:ok, n} = Server.Wake.put_back(identity.thread_id, identity.agent, params[:prompts] || [])
    ok(frame, %{"put_back" => n})
  end
end
