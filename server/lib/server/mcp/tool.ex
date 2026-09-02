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
