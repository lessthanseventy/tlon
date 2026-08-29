defmodule Server.MCP.Tool do
  @moduledoc """
  The slice-1 tool surface (pi doc §2a/§5.1) — every tool a thin caller of the
  contexts, never a second writer (§10). Identity (thread, agent, session) rides
  the connection via `Server.MCP.Identity`, so no tool takes a thread parameter:
  misdirection is unrepresentable. Grouped in one file the way `Server.Arbiter`
  groups its backends — one seam, several small faces.
  """

  @doc "A changeset's errors as one tool-error sentence."
  def changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end

defmodule Server.MCP.Tool.Register do
  @moduledoc """
  Claim a live session for this connection's (thread, agent). Call once at
  session start. Supersedes any crashed predecessor's session — the zombie guard.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP.Identity
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

    payload = %{
      "session_id" => session.id,
      "agent" => identity.agent,
      "thread_id" => identity.thread_id
    }

    {:reply, Response.json(Response.tool(), payload), frame}
  end
end

defmodule Server.MCP.Tool.PostMessage do
  @moduledoc """
  Post to this connection's thread — talk on your thread, don't work in the void.
  The author is the bound agent; a reply targets the quoted message's author.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP

  schema do
    field :body, :string, required: true
    field :reply_to, :integer, description: "Message id this replies to"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Channel.post(%{
           thread_id: identity.thread_id,
           author: identity.agent,
           body: params[:body],
           reply_to: params[:reply_to]
         }) do
      {:ok, message} ->
        {:reply, Response.json(Response.tool(), %{"message_id" => message.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.Dossier
  alias Server.MCP
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
    identity = MCP.Identity.from_frame(frame)

    result =
      case Map.get(params, :from_message) do
        nil -> bank_derived(params, identity)
        message_id -> bank_stated(message_id, params, identity)
      end

    case result do
      {:ok, fact} ->
        Recall.embed_on_write(fact)
        payload = %{"fact_id" => fact.id, "provenance" => fact.provenance}
        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
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

  defp normalize({:ok, fact}), do: {:ok, fact}

  defp normalize({:error, :not_the_operator}),
    do: {:error, "stated facts quote the operator's own words; that message is not his"}

  defp normalize({:error, %Ecto.Changeset{} = cs}), do: {:error, MCP.Tool.changeset_error(cs)}
end

defmodule Server.MCP.Tool.RaiseIssue do
  @moduledoc """
  Record a defect in the STACK itself — the machine's own tracker, never product
  work or a task question (a knowledge gap is a question; being stuck is a
  message). This thread is recorded as the discovery site.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :summary, :string, required: true
    field :evidence, :string, description: "Where the evidence is"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.raise_issue(%{
           thread_id: identity.thread_id,
           summary: params[:summary],
           evidence: Map.get(params, :evidence),
           found_by: identity.agent
         }) do
      {:ok, issue} ->
        {:reply, Response.json(Response.tool(), %{"issue_id" => issue.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.RecordDone do
  @moduledoc """
  Record work landed on this thread. Evidence is REQUIRED — the command run, the
  commit, the passing gate. A claim that something works is backed by having run
  it.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :text, :string, required: true, description: "What shipped, one line"

    field :evidence, :string,
      required: true,
      description: "What proves it: the command and its result, a commit, a green gate"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.record_event(%{
           thread_id: identity.thread_id,
           kind: "work_landed",
           detail: %{"summary" => params[:text], "evidence" => params[:evidence]}
         }) do
      {:ok, event} ->
        {:reply, Response.json(Response.tool(), %{"event_id" => event.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.GetBrief do
  @moduledoc """
  This thread's brief: goal, lead, learnings (with certainty), blockers, shipped,
  recent — each capped WITH a count. Use get_facts to read past a cap.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Board
  alias Server.MCP
  alias Server.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)
    brief = %Thread{id: identity.thread_id} |> Board.brief() |> MCP.Brief.scope()
    {:reply, Response.json(Response.tool(), brief), frame}
  end
end

defmodule Server.MCP.Tool.GetFacts do
  @moduledoc "Every fact on this thread, newest first — the full read past the brief's cap."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP
  alias Server.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)

    facts =
      %Thread{id: identity.thread_id}
      |> Dossier.facts_for_thread()
      |> Enum.map(&MCP.Brief.fact/1)

    {:reply, Response.json(Response.tool(), facts), frame}
  end
end

defmodule Server.MCP.Tool.GetMessages do
  @moduledoc "This thread's recent messages in chat order, capped by limit."
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP
  alias Server.Thread

  schema do
    field :limit, :integer, default: 50
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    messages =
      %Thread{id: identity.thread_id}
      |> Channel.recent_messages(params[:limit] || 50)
      |> Enum.map(&MCP.Brief.message/1)

    {:reply, Response.json(Response.tool(), messages), frame}
  end
end

defmodule Server.MCP.Tool.AddTodo do
  @moduledoc """
  Add a plan step to this thread — `add_todo` as you plan (pi doc §5 slice 3). Thread-
  scoped by the connection's identity; it opens open. Order is insertion order, so the
  brief's NEXT is simply the first one still open.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :text, :string, required: true, description: "The plan step, one line"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.add_todo(%{thread_id: identity.thread_id, text: params[:text]}) do
      {:ok, todo} ->
        {:reply, Response.json(Response.tool(), %{"todo_id" => todo.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.CompleteTodo do
  @moduledoc """
  Mark a plan step done — `complete_todo(id)` as you finish (pi doc §5 slice 3). The
  todo must belong to THIS connection's thread; completing another thread's step is
  refused, the same identity-scoping the whole channel rests on. Emits no event — DONE
  is a merged view, and `record_done` is the evidence-bearing verb for outcomes.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP
  alias Server.Todo

  schema do
    field :id, :integer, required: true, description: "The todo id (from add_todo or the brief)"
  end

  @impl true
  def execute(params, frame) do
    thread_id = MCP.Identity.from_frame(frame).thread_id

    case Dossier.todo(params[:id]) do
      %Todo{thread_id: ^thread_id} = todo ->
        {:ok, _done} = Dossier.complete_todo(todo)
        {:reply, Response.json(Response.tool(), %{"completed" => todo.id}), frame}

      nil ->
        {:reply, Response.error(Response.tool(), "no such todo: #{params[:id]}"), frame}

      %Todo{} ->
        {:reply, Response.error(Response.tool(), "that todo is on another thread"), frame}
    end
  end
end

defmodule Server.MCP.Tool.RaiseQuestion do
  @moduledoc """
  Surface a knowledge gap in the WORK — `raise_question(text)` (pi doc §5 slice 4).
  "does raxol support embedding?" Thread-scoped by the connection's identity; it opens
  open, and shows up as an UNKNOWN in every brief until resolved. Distinct from
  `raise_issue` (a defect in the STACK) — a question is what the work needs to know.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :text, :string, required: true, description: "The question — a knowledge gap in the work"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.raise_question(%{thread_id: identity.thread_id, text: params[:text]}) do
      {:ok, question} ->
        {:reply, Response.json(Response.tool(), %{"question_id" => question.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP
  alias Server.Question

  schema do
    field :id, :integer, required: true, description: "The question id (from raise_question or the brief)"
    field :resolution, :string, description: "The answer, if you have one"
  end

  @impl true
  def execute(params, frame) do
    thread_id = MCP.Identity.from_frame(frame).thread_id

    case Dossier.question(params[:id]) do
      %Question{thread_id: ^thread_id} = question ->
        {:ok, _resolved} = Dossier.resolve_question(question, Map.get(params, :resolution))
        {:reply, Response.json(Response.tool(), %{"resolved" => question.id}), frame}

      nil ->
        {:reply, Response.error(Response.tool(), "no such question: #{params[:id]}"), frame}

      %Question{} ->
        {:reply, Response.error(Response.tool(), "that question is on another thread"), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :cmd, :string, required: true, description: "The exact command you ran"
    field :exit, :integer, required: true, description: "Its real exit code (0 = passed)"
    field :tail, :string, description: "A short tail of the output"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.record_check(%{
           thread_id: identity.thread_id,
           cmd: params[:cmd],
           exit: params[:exit],
           tail: Map.get(params, :tail)
         }) do
      {:ok, event} ->
        {:reply, Response.json(Response.tool(), %{"event_id" => event.id, "kind" => event.kind}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.Fact
  alias Server.MCP

  schema do
    field :id, :integer, required: true, description: "The fact id (from the brief or get_facts)"

    field :exit, :integer,
      required: true,
      description: "The real exit code of re-running its check_cmd (0 = still passes)"

    field :tail, :string, description: "A short tail of the output"
  end

  @impl true
  def execute(params, frame) do
    thread_id = MCP.Identity.from_frame(frame).thread_id

    case Dossier.fact(params[:id]) do
      %Fact{thread_id: ^thread_id} = fact ->
        case Dossier.recheck_fact(fact, %{exit: params[:exit], tail: Map.get(params, :tail)}) do
          {:ok, event} ->
            {:reply, Response.json(Response.tool(), %{"event_id" => event.id, "kind" => event.kind}), frame}

          {:error, :no_check_cmd} ->
            {:reply, Response.error(Response.tool(), "fact #{params[:id]} has no check_cmd — nothing to re-run"), frame}

          {:error, changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end

      nil ->
        {:reply, Response.error(Response.tool(), "no such fact: #{params[:id]}"), frame}

      %Fact{} ->
        {:reply, Response.error(Response.tool(), "that fact is on another thread"), frame}
    end
  end
end

defmodule Server.MCP.Tool.OpenThread do
  @moduledoc """
  Open a NEW thread — a fresh unit of work. One of the two DELIBERATE cross-thread verbs:
  unlike every other tool, it does not act on the connection's own thread (there is no
  thread to misdirect — it is creating one). An orchestrator opens threads for work to be
  picked up; the returned id is how a pane is then spawned onto it (`Server.MCP.Spawn`).
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP

  schema do
    field :title, :string, required: true, description: "What the thread is for (its NORTH STAR)"
  end

  @impl true
  def execute(params, frame) do
    case Channel.open_thread(%{title: params[:title]}) do
      {:ok, thread} ->
        {:reply, Response.json(Response.tool(), %{"thread_id" => thread.id}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.StaffLeaf do
  @moduledoc """
  Open a NEW worker-led thread — the sanctioned "kick off a leaf" verb. Composes the cross-thread
  primitives: open a thread titled `title`, assign the registered agent `lead`, and post `brief`
  (authored by the CALLER's bound identity) as its opening message. Staffing, not spawning: no
  terminal starts here — the cockpit's convergent leaf sweep sees a worker-led thread without a
  window and stands one up (human-named, `@funes_thread`-tagged, leaf-cap-accounted, its harness
  server-bound). An agent never launches a harness by hand — a bare spawn is not a server citizen
  and is invisible to the board; it staffs the thread and lets the board actuate.

  The lead resolves BEFORE the thread opens, so a bad handle refuses cleanly instead of leaving an
  orphan leaderless thread — the machine-chat silence bug's tool-side twin.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Agent
  alias Server.Channel
  alias Server.MCP
  alias Server.Staff

  schema do
    field :title, :string, required: true, description: "What the leaf is for (its NORTH STAR)"
    field :lead, :string, required: true, description: "Registered worker handle to staff as lead (e.g. hronir-machine)"
    field :brief, :string, required: true, description: "The opening assignment, posted as the thread's first message"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    with {:agent, %Agent{}} <- {:agent, Staff.agent_by_name(params[:lead])},
         {:ok, thread} <- Channel.open_thread(%{title: params[:title]}),
         {:ok, _} <- Channel.assign_lead(thread.id, params[:lead]),
         {:ok, _} <- Channel.post(%{thread_id: thread.id, author: identity.agent, body: params[:brief]}) do
      {:reply, Response.json(Response.tool(), %{"thread_id" => thread.id, "lead" => params[:lead]}), frame}
    else
      {:agent, nil} ->
        {:reply,
         Response.error(
           Response.tool(),
           "no registered agent named #{inspect(params[:lead])} — staff a handle from the workspace roster"
         ), frame}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "staff_leaf failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.CloseThread do
  @moduledoc """
  Close a thread by id — the second DELIBERATE cross-thread verb. History outlives the
  close (messages are untouched); a closed thread just leaves the open list. It takes a
  thread id BY DESIGN — closing a peer's finished thread is the coordination act this verb
  exists for, the sanctioned exception to "no tool takes a thread parameter". A missing id
  is refused.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel

  schema do
    field :thread_id, :integer, required: true, description: "The thread to close"
  end

  @impl true
  def execute(params, frame) do
    case Channel.thread(params[:thread_id]) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such thread: #{params[:thread_id]}"), frame}

      thread ->
        {:ok, closed} = Channel.close_thread(thread)
        {:reply, Response.json(Response.tool(), %{"closed" => closed.id, "state" => closed.state}), frame}
    end
  end
end

defmodule Server.MCP.Tool.SwitchThread do
  @moduledoc """
  Move THIS connection onto another thread — the coordination act behind episode ROTATION. Mints a
  fresh token bound to `{thread_id, this agent}` and returns it; the adapter re-handshakes with it,
  so the agent's WARM session is untouched (its LLM cache stays) — only WHERE its posts land moves.
  The fourth deliberate cross-thread verb (after open/close_thread, consult_peer): it takes a thread
  id BY DESIGN. A missing thread (or agent) is refused — never mint against a guess.

  Minting here grants no access on its own — the same as `/mint` (127.0.0.1-only): the bearer still
  has to re-connect and `register`. So this is the SIGNAL half of the switch; the adapter that holds
  the connection performs the re-handshake with the returned token.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP.Identity
  alias Server.MCP.Spawn

  schema do
    field :thread_id, :integer, required: true, description: "The thread to move this connection onto"
  end

  @impl true
  def execute(params, frame) do
    agent = Identity.from_frame(frame).agent

    case Spawn.mint_for(params[:thread_id], agent) do
      {:ok, token} ->
        {:reply, Response.json(Response.tool(), %{"thread_id" => params[:thread_id], "token" => token}), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "cannot switch to thread #{params[:thread_id]}: #{inspect(reason)}"),
         frame}
    end
  end
end

defmodule Server.MCP.Tool.ConsultPeer do
  @moduledoc """
  Ask a peer agent a question — the third DELIBERATE cross-thread verb (after
  open_thread/close_thread). The caller names a peer AGENT, never a thread id; server
  resolves the peer's target thread (agent-filtered, with a defined tie-break) and
  delivers the ask there. The peer's answer is mirrored back to the caller's own thread
  (see `Server.Consult`), so the caller reads it in its own dossier. A missing or
  ambiguous peer is refused.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Consult
  alias Server.MCP

  schema do
    field :peer, :string, required: true, description: "The peer agent's name to ask"
    field :prompt, :string, required: true, description: "The question to ask the peer"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Consult.consult_peer(identity, params[:peer], params[:prompt]) do
      {:ok, %{consult_id: consult_id, peer_thread_id: peer_thread_id}} ->
        {:reply,
         Response.json(Response.tool(), %{
           "consult_id" => consult_id,
           "peer_thread_id" => peer_thread_id
         }), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "consult_peer failed: #{inspect(reason)}"), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Dossier
  alias Server.MCP

  schema do
    field :text, :string,
      required: true,
      description: "The working habit, imperative — e.g. 'run mise run check before proposing a commit'"

    field :rationale, :string, description: "Why it's worth adopting"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Dossier.propose_habit(%{
           text: params[:text],
           rationale: Map.get(params, :rationale),
           proposed_by: identity.agent,
           source_thread_id: identity.thread_id
         }) do
      {:ok, habit} ->
        {:reply, Response.json(Response.tool(), %{"habit_id" => habit.id, "state" => habit.state}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
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
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Search

  schema do
    field :query, :string, required: true, description: "Words to search for (multiple words AND together)"
    field :limit, :integer, description: "Max results to show (default 10)"
  end

  @impl true
  def execute(params, frame) do
    {:reply, Response.json(Response.tool(), Search.history(params[:query], params[:limit] || 10)), frame}
  end
end

defmodule Server.MCP.Tool.SearchFacts do
  @moduledoc """
  Search the FACT corpus — the whole ledger, past the brief's cap. Full-text, bm25-ranked. Use it
  to find a banked finding by a remembered word when it is not in the current thread's brief.
  Returns a `%{shown, more}` cut (fact id, thread, kind, text, snippet).
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Search

  schema do
    field :query, :string, required: true, description: "Words to search for (multiple words AND together)"
    field :limit, :integer, description: "Max results to show (default 10)"
  end

  @impl true
  def execute(params, frame) do
    {:reply, Response.json(Response.tool(), Search.facts(params[:query], params[:limit] || 10)), frame}
  end
end

defmodule Server.MCP.Tool.MachineOverview do
  @moduledoc """
  The machine META-view: every OPEN machine thread as a compact brief (title, lead, next step,
  open blockers, recent messages) — the cross-leaf read the Orbis Tertius meta agent synthesizes
  from (design: docs/plans/2026-08-19-orbis-tertius-meta-thread-design.md). Unlike the self-thread
  reads it spans threads, yet it honours "no tool takes a thread parameter": it takes none, and is
  served ONLY to a machine-scope connection — a project-scope agent is refused, so it reads across
  the machine workspace without becoming a cross-scope peephole.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Board
  alias Server.Channel
  alias Server.MCP.Identity

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)

    case Channel.thread(identity.thread_id) do
      %{scope: "machine"} ->
        {:reply, Response.json(Response.tool(), Board.machine_overview()), frame}

      _ ->
        {:reply, Response.error(Response.tool(), "machine_overview is for machine-scope threads only"), frame}
    end
  end
end

defmodule Server.MCP.Tool.SpawnCrew do
  @moduledoc """
  Staff a crew role onto THIS thread — the leader's spawn verb (server crew MVP). Mints the role's
  server identity on your thread and stands up its terminal, then hands it `task` as its opening
  assignment. MVP role is `reviewer`. Like every self-thread tool it takes no thread parameter: the
  role joins the connection's own thread, so a leader spawns a reviewer onto the work it is leading.

  Actuated by the configured crew backend (`Server.Crew`) — on the console hub that spawns the window
  in the live node. With no backend (the standalone service) it reports unavailable rather than
  faking a spawn.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Crew
  alias Server.MCP

  schema do
    field :task, :string, required: true, description: "The opening assignment — what the role should do"
    field :role, :string, description: "Crew role to staff (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.spawn_role(role, identity.thread_id, params[:task]) do
      {:ok, window} ->
        payload = %{"role" => role, "thread_id" => identity.thread_id, "window" => to_string(window)}
        {:reply, Response.json(Response.tool(), payload), frame}

      {:error, :no_crew} ->
        {:reply, Response.error(Response.tool(), "crew spawning is unavailable here — no crew backend is configured"),
         frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "crew spawn failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.KillCrew do
  @moduledoc """
  Tear down a crew role's terminal on THIS thread — the leader's teardown verb (server crew MVP).
  Thread-scoped by the connection's identity; role defaults to `reviewer`. Best-effort: a role that
  is already gone is not an error.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Crew
  alias Server.MCP

  schema do
    field :role, :string, description: "Crew role to tear down (default reviewer)"
  end

  @impl true
  def execute(params, frame) do
    identity = MCP.Identity.from_frame(frame)
    role = Map.get(params, :role) || "reviewer"

    case Crew.kill_role(role, identity.thread_id) do
      :ok ->
        {:reply, Response.json(Response.tool(), %{"killed" => role, "thread_id" => identity.thread_id}), frame}

      {:error, :no_crew} ->
        {:reply, Response.error(Response.tool(), "crew teardown is unavailable here — no crew backend is configured"),
         frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "crew kill failed: #{inspect(reason)}"), frame}
    end
  end
end

defmodule Server.MCP.Tool.RegisterWorkspace do
  @moduledoc """
  Register a WORKSPACE — a first-class composition (workspaces/orbis Slice 1): a git-tracked
  scope (`paths`), a `roster` of archetype instances, and free-form `knobs` that console
  reads to drive its picker/survey/spawn. Unlike the thread-scoped tools this is
  machine-GLOBAL — it takes no identity, it writes the shared `workspace` table via
  `Server.Workspaces`. `name` is unique; a duplicate is a graceful error, not a crash.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace's unique name"
    field :type, :enum, values: ["code", "life", "blank"], default: "code"
    field :scope, :enum, values: ["project", "machine"], default: "machine"
    field :paths, {:list, :string}, default: [], description: "Git-tracked scope globs"
    field :roster, {:list, :map}, default: [], description: "Archetype instances: {archetype,name,model?,knobs}"
    field :knobs, :map, default: %{}, description: "Free-form per-workspace settings"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.register(params) do
      {:ok, workspace} ->
        {:reply, Response.json(Response.tool(), %{"workspace_id" => workspace.id, "name" => workspace.name}), frame}

      {:error, changeset} ->
        {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
    end
  end
end

defmodule Server.MCP.Tool.ListWorkspaces do
  @moduledoc """
  Every WORKSPACE, newest-first — the machine-global read console's Orbis survey/picker maps
  over. Takes no identity: workspaces are not thread-scoped.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Workspaces

  schema do
  end

  @impl true
  def execute(_params, frame) do
    workspaces = Enum.map(Workspaces.all(), &MCP.Brief.workspace/1)
    {:reply, Response.json(Response.tool(), workspaces), frame}
  end
end

defmodule Server.MCP.Tool.EditWorkspace do
  @moduledoc """
  Edit a WORKSPACE's mutable fields (`type`/`scope`/`paths`/`roster`/`knobs`), identified by
  its unique `name` — a workspace's identity is immutable, so name is the handle, not a
  field this rewrites. Machine-global; a missing workspace is refused rather than created.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace to edit (its unique name)"
    field :type, :enum, values: ["code", "life", "blank"]
    field :scope, :enum, values: ["project", "machine"]
    field :paths, {:list, :string}, description: "Git-tracked scope globs"
    field :roster, {:list, :map}, description: "Archetype instances: {archetype,name,model?,knobs}"
    field :knobs, :map, description: "Free-form per-workspace settings"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.by_name(params[:name]) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such workspace: #{params[:name]}"), frame}

      workspace ->
        case Workspaces.edit(workspace, params) do
          {:ok, edited} ->
            {:reply, Response.json(Response.tool(), MCP.Brief.workspace(edited)), frame}

          {:error, changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.RemoveWorkspace do
  @moduledoc """
  Remove a WORKSPACE by its unique `name` — machine-global, thread-independent. A missing
  workspace is refused rather than reported as removed.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Workspaces

  schema do
    field :name, :string, required: true, description: "The workspace to remove (its unique name)"
  end

  @impl true
  def execute(params, frame) do
    case Workspaces.by_name(params[:name]) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such workspace: #{params[:name]}"), frame}

      workspace ->
        case Workspaces.remove(workspace) do
          {:ok, removed} ->
            {:reply, Response.json(Response.tool(), %{"removed" => removed.name}), frame}

          {:error, :last_workspace} ->
            {:reply,
             Response.error(
               Response.tool(),
               "refused: #{workspace.name} is the last workspace — threads must have a home"
             ), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.TrackThread do
  @moduledoc """
  Promote THIS connection's thread into the stage machine at "build" — tracking is
  the lazy path (reshape slice B): the harness hooks call this mechanically on the
  first successful `git commit`, so the ticket condenses out of the work. Agents may
  also call it deliberately ("track this thread"). Idempotent; self-thread like every
  write — no thread parameter exists to misdirect.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = MCP.Identity.from_frame(frame)

    case Repo.get(Thread, identity.thread_id) do
      nil ->
        {:reply, Response.error(Response.tool(), "no thread ##{identity.thread_id}"), frame}

      thread ->
        case Workline.promote(thread) do
          {:ok, tracked} ->
            payload = %{"stage" => tracked.stage, "slug" => tracked.slug}
            {:reply, Response.json(Response.tool(), payload), frame}

          {:error, :root_machine_thread} ->
            {:reply, Response.error(Response.tool(), "refused: the root machine thread is not a work item"), frame}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:reply, Response.error(Response.tool(), MCP.Tool.changeset_error(changeset)), frame}
        end
    end
  end
end

defmodule Server.MCP.Tool.PresenceThinking do
  @moduledoc """
  Declare THIS connection's agent thinking on its thread — call at turn start, so
  the cockpit shows "thinking" the moment work begins (thinking counts as working).
  Self-thread like every write: agent + thread resolve from the token, no args.
  Idempotent; a stuck declare is swept by `Server.Presence.Thinking`'s max-age guard.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP.Identity
  alias Server.Presence.Thinking

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    :ok = Thinking.thinking(identity.thread_id, identity.agent)
    {:reply, Response.json(Response.tool(), %{"thinking" => identity.agent, "thread_id" => identity.thread_id}), frame}
  end
end

defmodule Server.MCP.Tool.PresenceIdle do
  @moduledoc """
  Declare THIS connection's agent done thinking — call at turn end (and on session
  end as the crash safety net). A no-op when nothing was declared, so hooks can
  fire it unconditionally.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.MCP.Identity
  alias Server.Presence.Thinking

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame)
    :ok = Thinking.idle(identity.thread_id, identity.agent)
    {:reply, Response.json(Response.tool(), %{"idle" => identity.agent, "thread_id" => identity.thread_id}), frame}
  end
end

defmodule Server.MCP.Tool.AdvanceStage do
  @moduledoc """
  Advance THIS thread's workline past its current stage (worklines slice 1) — the single
  sanctioned mutation. Refused without the stage's owed artifact COMMITTED (the check lands
  in CHECKS either way); gated transitions (spec→plan, review→merged, machine-born intent)
  park `awaiting: andrew` — the operator approves, an agent never can. Identity-bound: no
  thread parameter, you advance the workline you are standing on.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP.Identity
  alias Server.Workline

  schema do
  end

  @impl true
  def execute(_params, frame) do
    thread_id = Identity.from_frame(frame).thread_id

    case Channel.thread(thread_id) do
      nil ->
        {:reply, Response.error(Response.tool(), "no such thread: #{thread_id}"), frame}

      thread ->
        reply(Workline.advance(thread), frame)
    end
  end

  defp reply({:ok, thread}, frame),
    do: {:reply, Response.json(Response.tool(), %{"stage" => thread.stage, "awaiting" => thread.awaiting}), frame}

  defp reply({:awaiting, thread}, frame),
    do:
      {:reply,
       Response.json(Response.tool(), %{
         "stage" => thread.stage,
         "awaiting" => thread.awaiting,
         "note" => "gated — the operator approves this transition"
       }), frame}

  defp reply({:error, {:artifact_missing, why}}, frame),
    do: {:reply, Response.error(Response.tool(), "owed artifact missing: #{why}"), frame}

  defp reply({:error, reason}, frame),
    do: {:reply, Response.error(Response.tool(), "cannot advance: #{inspect(reason)}"), frame}
end

defmodule Server.MCP.Tool.SubmitReview do
  @moduledoc """
  The write-fenced reviewer's ONE door (worklines slice 3): server writes and commits
  work/<slug>/review.md itself — the reviewer profile structurally cannot (write/edit
  denied). Identity-bound to THIS thread, refused outside the review stage. Verdict at
  the top of the body; then call advance_stage to hand the merge gate to the operator.
  """
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Server.Channel
  alias Server.MCP.Identity
  alias Server.Workline.Review

  schema do
    field :body, :string, required: true, description: "The full review.md content — verdict first, then findings"
  end

  @impl true
  def execute(params, frame) do
    identity = Identity.from_frame(frame)

    with %Server.Thread{} = thread <- Channel.thread(identity.thread_id) || {:error, :no_thread},
         {:ok, rel} <- Review.submit(thread, params[:body], identity.agent) do
      {:reply, Response.json(Response.tool(), %{"committed" => rel}), frame}
    else
      {:error, {:not_in_review, stage}} ->
        {:reply, Response.error(Response.tool(), "not in review — this workline is at #{stage}"), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "submit_review failed: #{inspect(reason)}"), frame}
    end
  end
end
