defmodule Server.MCP.Tool.Register do
  @moduledoc """
  Claim a live session for this connection's (thread, agent). Call once at
  session start. Supersedes any crashed predecessor's session — the zombie guard.
  """
  use Server.MCP.Tool

  alias Server.Staff

  schema do
    field :pane_ref, :string, description: "Opaque pane handle (e.g. $TMUX_PANE)"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    # The binding came from real rows, so an FK failure here is a bug that raises. The token needs
    # no updating — it is stateless, and later calls resolve this session via Staff.live_session/2.
    {:ok, session} =
      Staff.start_session(%{
        agent_id: identity.agent_id,
        thread_id: identity.thread_id,
        pane_ref: params[:pane_ref]
      })

    ok(frame, %{"session_id" => session.id, "agent" => identity.agent, "thread_id" => identity.thread_id})
  end
end

defmodule Server.MCP.Tool.PostMessage do
  @moduledoc """
  Post to this connection's thread — talk on your thread, don't work in the void.
  The author is the bound agent; a reply targets the quoted message's author.
  """
  use Server.MCP.Tool

  alias Server.Channel

  schema do
    field :body, :string, required: true
    field :reply_to, :integer, description: "Message id this replies to"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{thread_id: identity.thread_id, author: identity.agent, body: params[:body], reply_to: params[:reply_to]}
    |> Channel.post()
    |> then(&reply(frame, &1, fn message -> %{"message_id" => message.id} end))
  end
end

defmodule Server.MCP.Tool.BankFact do
  @moduledoc """
  Bank a durable fact on this thread. Your own finding is `derived` — pass
  `check_cmd` when the claim is reproducible, or it ranks as an unverified
  opinion. To bank the operator's words as a `stated` fact, pass `from_message`
  (his message id): the fact quotes it verbatim. Never paraphrase him into text.
  `intent` is optional on either path — what the fact is FOR, the purpose the
  value loop later grades against.
  """
  use Server.MCP.Tool

  alias Server.Channel
  alias Server.Dossier
  alias Server.Recall

  schema do
    field :kind, :enum, values: ["decision", "constraint", "learned"], required: true

    field :text, :string, description: "The single claim (omit when from_message quotes the operator)"

    field :check_cmd, :string, description: "Command that re-runs/verifies the claim"

    field :from_message, :integer, description: "Operator message id to quote verbatim as a STATED fact"

    field :intent, :string, description: "What this fact is FOR — the purpose the value loop later grades against"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    result =
      case Map.get(params, :from_message) do
        nil -> bank_derived(params, identity)
        message_id -> bank_stated(message_id, params, identity)
      end

    reply(frame, result, fn fact ->
      Recall.embed_on_write(fact)
      %{"fact_id" => fact.id, "provenance" => fact.provenance}
    end)
  end

  defp bank_derived(%{text: text} = params, identity) when is_binary(text) do
    %{
      thread_id: identity.thread_id,
      kind: params.kind,
      text: text,
      provenance: "derived",
      check_cmd: Map.get(params, :check_cmd),
      intent: Map.get(params, :intent),
      source_session_id: identity.session_id
    }
    |> Dossier.bank_fact()
    |> normalize()
  end

  defp bank_derived(_params, _identity), do: {:error, "text is required unless from_message quotes the operator"}

  defp bank_stated(message_id, params, identity) do
    message = Channel.message(message_id)

    cond do
      is_nil(message) ->
        {:error, "no message ##{message_id}"}

      message.thread_id != identity.thread_id ->
        {:error, "message ##{message_id} is not on this connection's thread"}

      true ->
        message
        |> Dossier.bank_stated_fact(%{
          kind: params.kind,
          check_cmd: Map.get(params, :check_cmd),
          intent: Map.get(params, :intent),
          source_session_id: identity.session_id
        })
        |> normalize()
    end
  end

  defp normalize({:error, :not_the_operator}),
    do: {:error, "stated facts quote the operator's own words; that message is not his"}

  defp normalize(result), do: result
end

defmodule Server.MCP.Tool.RaiseIssue do
  @moduledoc """
  Record a defect in the STACK itself — the machine's own tracker, never product
  work or a task question (a knowledge gap is a question; being stuck is a
  message). This thread is recorded as the discovery site.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :summary, :string, required: true
    field :evidence, :string, description: "Where the evidence is"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{
      thread_id: identity.thread_id,
      summary: params[:summary],
      evidence: Map.get(params, :evidence),
      found_by: identity.agent
    }
    |> Dossier.raise_issue()
    |> then(&reply(frame, &1, fn issue -> %{"issue_id" => issue.id} end))
  end
end

defmodule Server.MCP.Tool.RecordDone do
  @moduledoc """
  Record work landed on this thread. Evidence is REQUIRED — the command run, the
  commit, the passing gate. A claim that something works is backed by having run
  it.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :text, :string, required: true, description: "What shipped, one line"

    field :evidence, :string,
      required: true,
      description: "What proves it: the command and its result, a commit, a green gate"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{
      thread_id: identity.thread_id,
      kind: "work_landed",
      detail: %{"summary" => params[:text], "evidence" => params[:evidence]}
    }
    |> Dossier.record_event()
    |> then(&reply(frame, &1, fn event -> %{"event_id" => event.id} end))
  end
end

defmodule Server.MCP.Tool.AddTodo do
  @moduledoc """
  Add a plan step to this thread — `add_todo` as you plan (pi doc §5 slice 3). Thread-
  scoped by the connection's identity; it opens open. Order is insertion order, so the
  brief's NEXT is simply the first one still open.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :text, :string, required: true, description: "The plan step, one line"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{thread_id: identity.thread_id, text: params[:text]}
    |> Dossier.add_todo()
    |> then(&reply(frame, &1, fn todo -> %{"todo_id" => todo.id} end))
  end
end

defmodule Server.MCP.Tool.CompleteTodo do
  @moduledoc """
  Mark a plan step done — `complete_todo(id)` as you finish (pi doc §5 slice 3). The
  todo must belong to THIS connection's thread; completing another thread's step is
  refused, the same identity-scoping the whole channel rests on. Emits no event — DONE
  is a merged view, and `record_done` is the evidence-bearing verb for outcomes.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :id, :integer, required: true, description: "The todo id (from add_todo or the brief)"
  end

  @impl true
  def execute(params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    own(frame, thread_id, {"todo", params[:id], Dossier.todo(params[:id])}, fn todo ->
      {:ok, _done} = Dossier.complete_todo(todo)
      ok(frame, %{"completed" => todo.id})
    end)
  end
end

defmodule Server.MCP.Tool.RaiseQuestion do
  @moduledoc """
  Surface a knowledge gap in the WORK — `raise_question(text)` (pi doc §5 slice 4).
  "does raxol support embedding?" Thread-scoped by the connection's identity; it opens
  open, and shows up as an UNKNOWN in every brief until resolved. Distinct from
  `raise_issue` (a defect in the STACK) — a question is what the work needs to know.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :text, :string, required: true, description: "The question — a knowledge gap in the work"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{thread_id: identity.thread_id, text: params[:text]}
    |> Dossier.raise_question()
    |> then(&reply(frame, &1, fn question -> %{"question_id" => question.id} end))
  end
end

defmodule Server.MCP.Tool.ResolveQuestion do
  @moduledoc """
  Resolve a question — `resolve_question(id, resolution)` (pi doc §5 slice 4). The
  question must belong to THIS connection's thread; resolving another thread's is
  refused. `resolution` (the answer) is optional here — a DURABLE answer should also be
  `bank_fact`'d, since a resolved question closes the gap but a fact is what a successor
  reads as known.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :id, :integer, required: true, description: "The question id (from raise_question or the brief)"
    field :resolution, :string, description: "The answer, if you have one"
  end

  @impl true
  def execute(params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    own(frame, thread_id, {"question", params[:id], Dossier.question(params[:id])}, fn question ->
      {:ok, _resolved} = Dossier.resolve_question(question, Map.get(params, :resolution))
      ok(frame, %{"resolved" => question.id})
    end)
  end
end

defmodule Server.MCP.Tool.RecordCheck do
  @moduledoc """
  Record a MEASURED check (roadmap #5): the command you ran, its real `exit` code, and a
  `tail` of output. server lands a `check_passed` (exit 0) or `check_failed` event —
  evidence keyed on the NUMBER, never a self-report. Run the command yourself (via `cap`);
  this only records the outcome. Distinct from `record_done` (a judgement-worthy shipped
  outcome) — record_check is the honest "I ran it and here is what happened".
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :cmd, :string, required: true, description: "The exact command you ran"
    field :exit, :integer, required: true, description: "Its real exit code (0 = passed)"
    field :tail, :string, description: "A short tail of the output"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{thread_id: identity.thread_id, cmd: params[:cmd], exit: params[:exit], tail: Map.get(params, :tail)}
    |> Dossier.record_check()
    |> then(&reply(frame, &1, fn event -> %{"event_id" => event.id, "kind" => event.kind} end))
  end
end

defmodule Server.MCP.Tool.RecheckFact do
  @moduledoc """
  Re-verify a fact by re-running its OWN `check_cmd` — is the claim you are about to
  build on STILL true? Run the fact's command yourself (via `cap`) and report the real
  `exit` code; server lands a check keyed on that number and correlated to the fact, so a
  `check_failed` is the drift signal that a "checked" fact has gone stale. You give the
  fact `id` and the result, never a command — the command is the fact's own, pinned, so a
  re-verification cannot quietly prove a DIFFERENT claim. A fact with no `check_cmd` is
  unverifiable and is refused rather than faked.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :id, :integer, required: true, description: "The fact id (from the brief or get_facts)"

    field :exit, :integer,
      required: true,
      description: "The real exit code of re-running its check_cmd (0 = still passes)"

    field :tail, :string, description: "A short tail of the output"
  end

  @impl true
  def execute(params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    own(frame, thread_id, {"fact", params[:id], Dossier.fact(params[:id])}, fn fact ->
      case Dossier.recheck_fact(fact, %{exit: params[:exit], tail: Map.get(params, :tail)}) do
        {:error, :no_check_cmd} -> fail(frame, "fact #{params[:id]} has no check_cmd — nothing to re-run")
        result -> reply(frame, result, fn event -> %{"event_id" => event.id, "kind" => event.kind} end)
      end
    end)
  end
end

defmodule Server.MCP.Tool.ProposeHabit do
  @moduledoc """
  Propose a HABIT — how you should WORK with the operator (a durable working preference,
  not a fact about the world and not a task step). It lands PENDING: the operator approves
  it in console before it joins the always-loaded set every session reads. Distinct from a
  `stated` constraint (his verbatim words, which you cannot author) — a habit is YOUR
  proposal, promoted only by his approval. There is deliberately no `approve_habit` tool:
  an agent cannot approve its own suggestion.
  """
  use Server.MCP.Tool

  alias Server.Dossier

  schema do
    field :text, :string,
      required: true,
      description: "The working habit, imperative — e.g. 'run mise run check before proposing a commit'"

    field :rationale, :string, description: "Why it's worth adopting"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    %{
      text: params[:text],
      rationale: Map.get(params, :rationale),
      proposed_by: identity.agent,
      source_thread_id: identity.thread_id
    }
    |> Dossier.propose_habit()
    |> then(&reply(frame, &1, fn habit -> %{"habit_id" => habit.id, "state" => habit.state} end))
  end
end

defmodule Server.MCP.Tool.PresenceThinking do
  @moduledoc """
  Declare THIS connection's agent thinking on its thread — call at turn start, so
  the cockpit shows "thinking" the moment work begins (thinking counts as working).
  Self-thread like every write: agent + thread resolve from the token, no args.
  Idempotent; a stuck declare is swept by `Server.Presence.Thinking`'s max-age guard.
  """
  use Server.MCP.Tool

  alias Server.Presence.Thinking

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    :ok = Thinking.thinking(identity.thread_id, identity.agent)
    ok(frame, %{"thinking" => identity.agent, "thread_id" => identity.thread_id})
  end
end

defmodule Server.MCP.Tool.PresenceIdle do
  @moduledoc """
  Declare THIS connection's agent done thinking — call at turn end (and on session
  end as the crash safety net). A no-op when nothing was declared, so hooks can
  fire it unconditionally.
  """
  use Server.MCP.Tool

  alias Server.Presence.Thinking

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    :ok = Thinking.idle(identity.thread_id, identity.agent)
    ok(frame, %{"idle" => identity.agent, "thread_id" => identity.thread_id})
  end
end
