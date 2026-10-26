defmodule Server.MCP.Tool.OperatorInbox do
  @moduledoc """
  What waits on the operator (`Server.Office.Needs.grouped/1`), for the manager's scheduled sweep
  and Uqbar's inbox loop: each item with its `key` and `route` and `asking`, the newest message on
  its thread that a server notice didn't write, so a restart notice posted after a coworker's
  question never hides the question. `route: uqbar` items are Uqbar's to settle or pass up
  (`settle_need`, `pass_up_need`); settled ones are the digest, not the inbox, and are omitted.
  Read-only: the operator's gates and questions stay theirs to answer.
  """
  use Server.MCP.Tool

  import Ecto.Query

  alias Server.Message
  alias Server.Repo

  schema do
  end

  @impl true
  def execute(_params, frame) do
    g = Server.Office.Needs.grouped()
    ok(frame, for(group <- ~w(uqbar phone machine clipboard)a, n <- g[group], do: render(n)))
  end

  defp render(n) do
    %{
      "key" => n.key,
      "route" => n.route,
      "recommendation" => n.recommendation,
      "why" => n.why,
      "kind" => n.kind,
      "level" => n.level,
      "thread_id" => n.thread_id,
      "title" => n.title,
      "text" => n.text,
      "asking" => n.thread_id && asking(n.thread_id)
    }
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
