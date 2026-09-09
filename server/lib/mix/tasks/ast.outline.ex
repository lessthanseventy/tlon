defmodule Mix.Tasks.Ast.Outline do
  @shortdoc "Outline a file's modules and defs: mix ast.outline [--json] FILE..."
  @moduledoc """
  `mix ast.outline [--json] lib/a.ex …` — each module with its moduledoc line and line span, then
  its defs (`kind name/arity  L<from>-<to>  — doc`); `--json` prints the data instead
  (`Server.Source.Outline.run/1`'s shape) for a tool to read.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Source.Outline

  @impl true
  def run(argv) do
    {opts, files, _} = OptionParser.parse(argv, strict: [json: :boolean])
    if files == [], do: Mix.raise("usage: mix ast.outline [--json] FILE...")

    for file <- files do
      case Outline.run(File.read!(file)) do
        {:ok, modules} -> print(file, modules, opts[:json] == true)
        {:error, reason} -> Mix.shell().error("#{file}: not parseable — #{inspect(reason)}")
      end
    end
  end

  defp print(file, modules, true), do: Mix.shell().info(JSON.encode!(%{file: file, modules: modules}))

  defp print(file, modules, false) do
    Mix.shell().info(file)
    Enum.each(modules, &print_module(&1, "  "))
  end

  defp print_module(m, indent) do
    {a, b} = m.lines || {0, 0}
    Mix.shell().info("#{indent}#{m.module}  L#{a}-#{b}#{if m.doc, do: "  — " <> m.doc, else: ""}")

    for d <- m.defs do
      {da, db} = d.lines || {0, 0}

      Mix.shell().info(
        "#{indent}  #{d.kind} #{d.name}/#{d.arity}  L#{da}-#{db}#{if d.doc, do: "  — " <> d.doc, else: ""}"
      )
    end

    Enum.each(m.modules, &print_module(&1, indent <> "  "))
  end
end
