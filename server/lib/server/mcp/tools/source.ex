defmodule Server.MCP.Tool.RenameIdentifier do
  @moduledoc """
  Rename an identifier across files in THIS thread's worktree, AST-aware (`Server.Source.Rename`):
  every def head, call, capture and variable named `old` becomes `new`; strings stay; `atoms`
  also renames `:old`/`old:`, `comments` the whole-word mentions in `#` comments. Only the
  identifier's bytes move. Paths are relative to the worktree and may not leave it.
  """
  use Server.MCP.Tool

  alias Server.Source.Tools

  schema do
    field :old, :string, required: true, description: "The identifier as it is"
    field :new, :string, required: true, description: "The identifier as it should be"
    field :files, {:list, :string}, required: true, description: "Paths relative to the worktree"
    field :atoms, :boolean, description: "Also rename the atom :old and the key old:"
    field :comments, :boolean, description: "Also rename whole-word mentions inside # comments"
  end

  @impl true
  def execute(params, frame) do
    with_thread(frame, fn thread ->
      opts = [atoms: params[:atoms] == true, comments: params[:comments] == true]

      case Tools.rename(thread, params.files, params.old, params.new, opts) do
        {:ok, result} -> ok(frame, %{"changed" => result.changed, "unchanged" => result.unchanged})
        {:error, message} -> fail(frame, message)
      end
    end)
  end

  @doc false
  def with_thread(frame, fun) do
    id = Identity.from_frame(frame).thread_id

    case Server.Channel.thread(id) do
      nil -> fail(frame, "no thread ##{id}")
      thread -> fun.(thread)
    end
  end
end

defmodule Server.MCP.Tool.OutlineFile do
  @moduledoc """
  A file in THIS thread's worktree as an outline (`Server.Source.Outline`): its modules, each
  with the moduledoc's first line, its line span, and its defs — kind, name/arity, the @doc line
  and @spec, the lines the clause spans. Read this before editing; it is cheaper than the file.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.RenameIdentifier
  alias Server.Source.Tools

  schema do
    field :file, :string, required: true, description: "A path relative to the worktree"
  end

  @impl true
  def execute(%{file: file}, frame) do
    RenameIdentifier.with_thread(frame, fn thread ->
      case Tools.outline(thread, file) do
        {:ok, result} -> ok(frame, result)
        {:error, message} -> fail(frame, message)
      end
    end)
  end
end
