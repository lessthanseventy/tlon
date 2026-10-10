defmodule Server.MCP.Tool.MarginNote do
  @moduledoc """
  Write one line in the room's margin (a `margin` note on this workspace's root thread). One short
  line per thing you did or noticed: `#174 back to build — the cake never drew`, `cut 650fa4a`.
  Name a thread as `#N` and the office lights that card when the note is hovered. It wakes nobody.
  """
  use Server.MCP.Tool

  alias Server.{Channel, Repo, Thread}

  @max 140

  schema do
    field :text, :string, required: true, description: "One line, ≤ #{@max} chars"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    text = String.trim(params[:text] || "")

    with :ok <- check(text),
         %Thread{workspace_id: ws} <- Repo.get(Thread, identity.thread_id),
         %Thread{id: root} <- Channel.machine_thread(ws) do
      result = Channel.post(%{thread_id: root, author: identity.agent, body: text, kind: "margin"})
      reply(frame, result, fn m -> %{"note_id" => m.id} end)
    else
      {:error, why} -> fail(frame, why)
      _ -> fail(frame, "no root thread to write the margin on")
    end
  end

  defp check(""), do: {:error, "a margin note needs text"}
  defp check(t), do: if(String.length(t) > @max, do: {:error, "one line, ≤ #{@max} chars"}, else: :ok)
end
