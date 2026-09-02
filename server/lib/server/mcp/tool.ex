defmodule Server.MCP.Tool do
  @moduledoc """
  The tool surface's one seam (pi doc §2a/§5.1): every tool is a thin caller of a context, never
  a second writer (§10), and identity (thread, agent, session) rides the connection via
  `Server.MCP.Identity`, so no self-thread tool takes a thread parameter — misdirection is
  unrepresentable. `use Server.MCP.Tool` makes a module an anubis tool component and imports the
  reply helpers below; the tools themselves live in `lib/server/mcp/tools/<family>.ex`.
  """
  alias Anubis.Server.Frame
  alias Anubis.Server.Response

  defmacro __using__(_opts) do
    quote do
      use Anubis.Server.Component, type: :tool

      import Server.MCP.Tool, only: [ok: 2, fail: 2, reply: 3, own: 4]

      alias Server.MCP.Identity, warn: false
    end
  end

  @typedoc "What a tool's `execute/2` returns."
  @type tool_reply :: {:reply, Response.t(), Frame.t()}

  @doc "A successful tool reply carrying `payload` as JSON."
  @spec ok(Frame.t(), term()) :: tool_reply()
  def ok(frame, payload), do: {:reply, Response.json(Response.tool(), payload), frame}

  @doc "A tool-error reply with `message`."
  @spec fail(Frame.t(), String.t()) :: tool_reply()
  def fail(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}

  @doc """
  Reply from a context result: `{:ok, row}` renders `render.(row)`; a changeset error becomes
  one sentence (`changeset_error/1`); a string reason is the message verbatim. Any other reason
  is the tool's to word — map it before calling.
  """
  @spec reply(Frame.t(), {:ok, term()} | {:error, Ecto.Changeset.t() | String.t()}, (term() -> term())) ::
          tool_reply()
  def reply(frame, {:ok, row}, render), do: ok(frame, render.(row))
  def reply(frame, {:error, %Ecto.Changeset{} = changeset}, _render), do: fail(frame, changeset_error(changeset))
  def reply(frame, {:error, reason}, _render) when is_binary(reason), do: fail(frame, reason)

  @doc """
  Act on a row that must belong to THIS connection's thread — the identity scoping every
  by-id tool rests on. `{noun, id, row}`: a nil row is "no such <noun>: <id>", another thread's
  row is refused, and only an own row reaches `fun`.
  """
  @spec own(Frame.t(), integer(), {String.t(), term(), struct() | nil}, (struct() -> tool_reply())) :: tool_reply()
  def own(frame, _thread_id, {noun, id, nil}, _fun), do: fail(frame, "no such #{noun}: #{id}")
  def own(_frame, thread_id, {_noun, _id, %{thread_id: thread_id} = row}, fun), do: fun.(row)
  def own(frame, _thread_id, {noun, _id, _row}, _fun), do: fail(frame, "that #{noun} is on another thread")

  @doc """
  The `workspace_id` of the connection's bound thread — the "current workspace" the
  workspace-scoped container tools (tickets/notes/projects) write into, since identity
  carries a thread, not a workspace. `nil` if the thread is gone.
  """
  def workspace_of(%{thread_id: thread_id}) do
    case Server.Repo.get(Server.Thread, thread_id) do
      %Server.Thread{workspace_id: wid} -> wid
      _ -> nil
    end
  end

  @doc "A changeset's errors as one tool-error sentence."
  def changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
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
