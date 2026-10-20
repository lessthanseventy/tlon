defmodule Server.MCP.Tool.ToolDenied do
  @moduledoc """
  The adapter's report that this seat's permission check refused a tool call: recorded as a
  `tool_denied` event on the thread, which `Server.Office.Needs` reads when the seat stays refused
  with nobody working. An adapter verb (`Server.MCP.Tool.adapter_verbs/0`): cut from the seat's
  model, called by the mod.
  """
  use Server.MCP.Tool

  schema do
    field :tool, :string, required: true, description: "The refused tool, e.g. Bash"
    field :summary, :string, description: "The call in one line, its target and never contents"
    field :reason, :string, description: "The permission check's reason for refusing it, as it gave it"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    {:ok, _} =
      Server.Dossier.record_event(%{
        thread_id: identity.thread_id,
        kind: "tool_denied",
        correlation: "tool_denied:#{identity.thread_id}",
        detail: %{
          "agent" => identity.agent,
          "tool" => params[:tool],
          "summary" => params[:summary],
          "reason" => params[:reason]
        }
      })

    ok(frame, %{"recorded" => true})
  end
end
