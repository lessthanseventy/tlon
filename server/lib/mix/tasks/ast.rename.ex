defmodule Mix.Tasks.Ast.Rename do
  @shortdoc "Rename an identifier AST-aware: mix ast.rename OLD NEW [--atoms] FILE..."
  @moduledoc """
  `mix ast.rename old_name new_name [--atoms] lib/a.ex lib/b.ex …`

  Every def/defp head, call, capture and variable named OLD becomes NEW; strings and comments
  stay. `--atoms` also renames the atom `:old` and the key `old:`. Files that don't change are
  not rewritten; an unparseable file is reported and skipped. Runs `mix format` on what it wrote.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Source.Rename

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [atoms: :boolean])

    case args do
      [old, new | files] when files != [] ->
        written = Enum.filter(files, &rewrite(&1, old, new, opts))
        if written != [], do: Mix.Task.run("format", written)
        Mix.shell().info("ast.rename: #{old} → #{new} in #{length(written)} of #{length(files)} file(s)")

      _ ->
        Mix.raise("usage: mix ast.rename OLD NEW [--atoms] FILE...")
    end
  end

  defp rewrite(file, old, new, opts) do
    source = File.read!(file)

    case Rename.run(source, old, new, atoms: opts[:atoms] == true) do
      {:error, reason} ->
        Mix.shell().error("#{file}: not parseable, skipped — #{inspect(reason)}")
        false

      ^source ->
        false

      out ->
        File.write!(file, out)
        true
    end
  end
end
