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
