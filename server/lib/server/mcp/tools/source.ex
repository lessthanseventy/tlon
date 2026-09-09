defmodule Server.MCP.Tool.RenameIdentifier do
  @moduledoc """
  Rename an identifier across files in THIS thread's worktree, AST-aware (`Menard.Rename`):
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
  A file in THIS thread's worktree as an outline (`Menard.Outline`): its modules, each
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

defmodule Server.MCP.Tool.EditClause do
  @moduledoc """
  Edit ONE clause of a function in a file in THIS thread's worktree (`Menard.Clause`):
  `verb` is `replace` (the body becomes `code`), `delete`, or `insert_after` (`code` is the new
  clause, placed right after). Address the clause by `name_arity` ("go/1") and `head` — its args
  as written plus any guard ("x when is_integer(x)"). A miss lists the heads that exist. Only the
  clause's bytes change; the file is left formatted by the caller's next format/check.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.RenameIdentifier
  alias Server.Source.Tools

  schema do
    field :verb, :enum, values: ["replace", "delete", "insert_after"], required: true
    field :file, :string, required: true, description: "A path relative to the worktree"
    field :name_arity, :string, required: true, description: ~s|e.g. "go/1"|

    field :head, :string,
      required: true,
      description: ~s|the clause's args as written, e.g. ":b" or "x when is_integer(x)"|

    field :code, :string, description: "replace: the new body; insert_after: the new clause"
  end

  @impl true
  def execute(params, frame) do
    RenameIdentifier.with_thread(frame, fn thread ->
      verb = String.to_existing_atom(params.verb)

      case Tools.clause(thread, verb, params.file, params.name_arity, params.head, params[:code]) do
        {:ok, result} -> ok(frame, result)
        {:error, message} -> fail(frame, message)
      end
    end)
  end
end

defmodule Server.MCP.Tool.RunVerb do
  @moduledoc """
  Run a verb in THIS thread's worktree and get ONE structured answer: `check` (the app's gate),
  `test` (args: files, `file:line`), `format` (args: files; reports what changed), `compile`
  (warnings as diagnostics). `ok` says whether it passed; `tail` is the last lines of output.
  Prefer this to a shell chain: the answer is data, and the gate is the same one the operator runs.
  """
  use Server.MCP.Tool

  alias Server.MCP.Tool.RenameIdentifier
  alias Server.Source.Tools

  schema do
    field :verb, :enum, values: ["check", "test", "format", "compile"], required: true
    field :args, {:list, :string}, description: "test: files or file:line; format: files"
  end

  @impl true
  def execute(params, frame) do
    RenameIdentifier.with_thread(frame, fn thread ->
      case Tools.run(thread, String.to_existing_atom(params.verb), params[:args] || []) do
        {:ok, result} -> ok(frame, result)
        {:error, message} -> fail(frame, message)
      end
    end)
  end
end
