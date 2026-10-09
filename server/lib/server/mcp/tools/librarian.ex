defmodule Server.MCP.Tool.Librarian do
  @moduledoc false

  @doc "A curation refusal as one sentence."
  def why(:no_reason), do: "give the reason — it stays on the record"
  def why(:same_fact), do: "a fact cannot supersede itself"
  def why(:not_found), do: "no such fact in this workspace"
  def why(:stated), do: "that is a stated fact — the operator's words; ask_operator to change it"
  def why(:forgotten), do: "that fact is already forgotten"
  def why({:already_supersedes, id}), do: "the newer fact already supersedes fact #{id}"
  def why(:not_a_proposal), do: "no such proposal in this workspace"
  def why(:bad_decision), do: "decision must be apply or reject"
  def why(:judge_not_installed), do: "the correction judge isn't installed on this server — nothing changed"
  def why(:mentions_operator), do: "no @mention of the operator in the report"
  def why(:no_lobby), do: "this workspace has no lobby to post in"
  def why(other), do: inspect(other)
end

defmodule Server.MCP.Tool.SupersedeFact do
  @moduledoc """
  Retire an older fact behind a newer one that restates or corrects it: the newer fact's
  `supersedes` points at the older, which recall then demotes, and your reason is recorded. Refused
  for a stated fact (the operator's words — ask_operator instead) and without a reason.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.Librarian, as: L

  schema do
    field :old_id, :integer, required: true, description: "The fact to retire"
    field :new_id, :integer, required: true, description: "The fact that replaces it"
    field :reason, :string, required: true, description: "Why, in one line"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    opts = [by: identity.agent, thread_id: identity.thread_id, workspace_id: Server.MCP.Tool.workspace_of(identity)]

    case Server.Librarian.supersede(params[:old_id], params[:new_id], params[:reason], opts) do
      {:ok, new} -> ok(frame, %{"fact" => new.id, "supersedes" => new.supersedes})
      {:error, why} -> fail(frame, L.why(why))
    end
  end
end

defmodule Server.MCP.Tool.ForgetFact do
  @moduledoc """
  Forget a fact — junk (placeholder text), or wrong with nothing to replace it. A tombstone: out of
  every recall surface, the row and your reason kept. Refused for a stated fact and without a reason.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.Librarian, as: L

  schema do
    field :fact_id, :integer, required: true, description: "The fact to forget"
    field :reason, :string, required: true, description: "Why, in one line"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    opts = [by: identity.agent, thread_id: identity.thread_id, workspace_id: Server.MCP.Tool.workspace_of(identity)]

    case Server.Librarian.forget(params[:fact_id], params[:reason], opts) do
      {:ok, fact} -> ok(frame, %{"forgot" => fact.id})
      {:error, why} -> fail(frame, L.why(why))
    end
  end
end

defmodule Server.MCP.Tool.ReviewProposals do
  @moduledoc """
  The correction judge's open proposals in this workspace, oldest first: each its `event_id`, the
  judge's verdict and reason, and both facts (`new` would supersede `old`) with their text. Decide
  each with decide_proposal.
  """
  use Server.MCP.Tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    ok(frame, Server.Librarian.proposals(Server.MCP.Tool.workspace_of(Identity.from_frame(frame))))
  end
end

defmodule Server.MCP.Tool.DecideProposal do
  @moduledoc """
  Decide one of the correction judge's proposals: `apply` (the new fact supersedes the old; refused
  over a stated fact) or `reject` (they are different claims — say why). Without the judge installed
  on this server it says so and changes nothing.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.Librarian, as: L

  schema do
    field :event_id, :integer, required: true, description: "The proposal (from review_proposals)"
    field :decision, :string, required: true, description: "apply | reject"
    field :reason, :string, description: "Why — required to reject"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)
    opts = [by: identity.agent, workspace_id: Server.MCP.Tool.workspace_of(identity)]

    case Server.Librarian.decide(params[:event_id], params[:decision], params[:reason], opts) do
      {:error, why} -> fail(frame, L.why(why))
      result -> ok(frame, %{"decided" => params[:decision], "result" => inspect(result)})
    end
  end
end

defmodule Server.MCP.Tool.KnowledgeReport do
  @moduledoc """
  The weekly state of the office's knowledge, posted in this workspace's lobby: the server counts
  the facts (live by provenance, superseded, this week's banked and forgotten, the shaky ones, the
  proposals waiting) and your `notes` follow — what changed and what is shaky, in a few lines. No
  @mention of the operator.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.Librarian, as: L

  schema do
    field :notes, :string, required: true, description: "What changed this week and what is shaky"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    case Server.Librarian.report(Server.MCP.Tool.workspace_of(identity), params[:notes], by: identity.agent) do
      {:ok, message} -> ok(frame, %{"message_id" => message.id, "thread_id" => message.thread_id})
      {:error, why} -> fail(frame, L.why(why))
    end
  end
end
