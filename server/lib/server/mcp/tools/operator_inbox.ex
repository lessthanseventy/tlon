defmodule Server.MCP.Tool.OperatorInbox do
  @moduledoc """
  What waits on the operator (`Server.Office.Needs.list/0`), for the manager's scheduled sweep:
  each item with `asking`, the newest message on its thread that a server notice didn't write, so
  a restart notice posted after a coworker's question never hides the question. Read-only: the
  operator's gates and questions stay theirs to answer.
  """
  use Server.MCP.Tool

  import Ecto.Query

  alias Server.Message
  alias Server.Repo

  schema do
  end

  @impl true
  def execute(_params, frame) do
    ok(
      frame,
      for n <- Server.Office.Needs.list() do
        %{
          "kind" => n.kind,
          "level" => n.level,
          "thread_id" => n.thread_id,
          "title" => n.title,
          "text" => n.text,
          "asking" => n.thread_id && asking(n.thread_id)
        }
      end
    )
  end

  defp asking(thread_id) do
    Repo.one(
      from m in Message,
        where: m.thread_id == ^thread_id and m.author != "tlon",
        order_by: [desc: m.id],
        limit: 1,
        select: fragment("? || ': ' || left(?, 1200)", m.author, m.body)
    )
  end
end
