defmodule Mix.Tasks.Ast.Clause do
  @shortdoc "Edit one clause: mix ast.clause (replace|delete|insert-after) FILE name/arity HEAD [CODE]"
  @moduledoc """
  `mix ast.clause replace lib/a.ex go/1 ':b' '20'` — swap the clause's body.
  `mix ast.clause delete lib/a.ex go/1 ':a'` — remove the clause (and its glued comment).
  `mix ast.clause insert-after lib/a.ex go/1 ':a' 'def go(:c), do: 3'` — add a clause after it.

  HEAD is the clause's args as written, plus its guard (`'x when is_integer(x)'`); whitespace is
  ignored. CODE may span lines (a block body). Only the clause's bytes change
  (`Server.Source.Clause`); the file is formatted after. A miss lists the clauses that exist.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Source.Clause

  @impl true
  def run(argv) do
    case argv do
      ["replace", file, na, head, code] -> write(file, Clause.replace_body(File.read!(file), na, head, code))
      ["delete", file, na, head] -> write(file, Clause.delete(File.read!(file), na, head))
      ["insert-after", file, na, head, code] -> write(file, Clause.insert_after(File.read!(file), na, head, code))
      _ -> Mix.raise("usage: mix ast.clause (replace|delete|insert-after) FILE name/arity HEAD [CODE]")
    end
  end

  defp write(_file, {:error, message}), do: Mix.raise(message)

  defp write(file, out) do
    File.write!(file, out)
    Mix.Task.run("format", [file])
    Mix.shell().info("ast.clause: #{file} written")
  end
end
