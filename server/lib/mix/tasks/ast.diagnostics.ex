defmodule Mix.Tasks.Ast.Diagnostics do
  @shortdoc "Compiler diagnostics as data: mix ast.diagnostics [--json]"
  @moduledoc """
  `mix ast.diagnostics [--json]` — a forced compile with warnings as data: one line per
  diagnostic (`file:line severity message`), or `--json`. Exit status 1 when anything is
  reported, so a caller can gate on it. The `Code.with_diagnostics/2` seam the compiler exposes.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [json: :boolean])

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          Mix.Task.run("compile", ["--force", "--no-deps-check"])
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    rows =
      Enum.map(diagnostics, fn d ->
        %{
          file: d[:file] && Path.relative_to_cwd(d.file),
          line: line_of(d[:position]),
          severity: d.severity,
          message: d.message
        }
      end)

    if opts[:json] == true,
      do: Mix.shell().info(JSON.encode!(rows)),
      else: Enum.each(rows, &Mix.shell().info("#{&1.file}:#{&1.line} #{&1.severity} #{&1.message}"))

    if rows != [], do: exit({:shutdown, 1})
  end

  defp line_of({line, _col}), do: line
  defp line_of(line) when is_integer(line), do: line
  defp line_of(_other), do: 0
end
