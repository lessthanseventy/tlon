defmodule Server.MCP.Tool.GetBrief do
  @moduledoc """
  This thread's brief: goal, lead, learnings (with certainty), blockers, shipped,
  recent — each capped WITH a count. Use get_facts to read past a cap.
  """
  use Server.MCP.Tool

  alias Server.Board
  alias Server.MCP
  alias Server.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    ok(frame, %Thread{id: identity.thread_id} |> Board.brief() |> MCP.Brief.scope())
  end
end

defmodule Server.MCP.Tool.GetFacts do
  @moduledoc "Every fact on this thread, newest first — the full read past the brief's cap."
  use Server.MCP.Tool

  alias Server.Dossier
  alias Server.MCP
  alias Server.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    ok(frame, %Thread{id: identity.thread_id} |> Dossier.facts_for_thread() |> Enum.map(&MCP.Brief.fact/1))
  end
end

defmodule Server.MCP.Tool.GetMessages do
  @moduledoc "This thread's recent messages in chat order, capped by limit."
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.MCP
  alias Server.Thread

  schema do
    field :limit, :integer, default: 50
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    messages =
      %Thread{id: identity.thread_id}
      |> Channel.recent_messages(params[:limit] || 50)
      |> Enum.map(&MCP.Brief.message/1)

    ok(frame, messages)
  end
end

defmodule Server.MCP.Tool.SearchHistory do
  @moduledoc """
  Search PAST conversations across the whole channel — episodic recall the curated brief does not
  hold. Full-text, bm25-ranked; a multi-word query ANDs its terms. Reach for it to answer "did we
  ever discuss X" or "what did we decide about Y" when it was never banked as a durable fact.
  Returns a `%{shown, more}` cut: the best matches (message id, thread, author, a snippet) and a
  count of the rest.
  """
  use Server.MCP.Tool

  alias Server.Search

  schema do
    field :query, :string, required: true, description: "Words to search for (multiple words AND together)"
    field :limit, :integer, description: "Max results to show (default 10)"
  end

  @impl true
  def execute(params, frame), do: ok(frame, Search.history(params[:query], params[:limit] || 10))
end

defmodule Server.MCP.Tool.SearchFacts do
  @moduledoc """
  Search the FACT corpus — the whole ledger, past the brief's cap. Full-text, bm25-ranked. Use it
  to find a banked finding by a remembered word when it is not in the current thread's brief.
  Returns a `%{shown, more}` cut (fact id, thread, kind, text, snippet).
  """
  use Server.MCP.Tool

  alias Server.Search

  schema do
    field :query, :string, required: true, description: "Words to search for (multiple words AND together)"
    field :limit, :integer, description: "Max results to show (default 10)"
  end

  @impl true
  def execute(params, frame), do: ok(frame, Search.facts(params[:query], params[:limit] || 10))
end

defmodule Server.MCP.Tool.MachineOverview do
  @moduledoc """
  The machine META-view: every OPEN machine thread as a compact brief (title, lead, next step,
  open blockers, recent messages) — the cross-thread read the Orbis Tertius meta agent synthesizes
  from (design: docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md). Unlike the self-thread
  reads it spans threads, yet it honours "no tool takes a thread parameter": it takes none, and is
  served ONLY to a machine-scope connection — a project-scope agent is refused, so it reads across
  the machine workspace without becoming a cross-scope peephole.
  """
  use Server.MCP.Tool

  alias Server.Board
  alias Server.Channel

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)

    case Channel.thread(identity.thread_id) do
      %{scope: "machine"} -> ok(frame, Board.machine_overview())
      _ -> fail(frame, "machine_overview is for machine-scope threads only")
    end
  end
end
