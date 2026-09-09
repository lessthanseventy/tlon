defmodule Mix.Tasks.Ast.Inspect do
  @shortdoc "Introspect the app: mix ast.inspect (callers MOD[.fun/arity]|exports|deps) [--json]"
  @moduledoc """
  The read-only verbs that look across files (single-engine, Mix):

      mix ast.inspect callers Server.Worktree          # files calling into a module (mix xref)
      mix ast.inspect callers Server.Worktree.ensure/2
      mix ast.inspect exports                          # the :boundary surface a consumer may call
      mix ast.inspect deps                             # outdated packages + advisories (hex)

  `--json` prints data; otherwise one line per row.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @impl true
  def run(argv) do
    {opts, args, _} = OptionParser.parse(argv, strict: [json: :boolean])
    json? = opts[:json] == true

    case args do
      ["callers", target] -> emit(json?, %{target: target, callers: callers(target)}, fn r -> r.callers end)
      ["exports"] -> emit(json?, %{exports: exports()}, fn r -> r.exports end)
      ["deps"] -> emit(json?, deps(), fn r -> r.outdated ++ r.advisories end)
      _ -> Mix.raise("usage: mix ast.inspect (callers MOD[.fun/arity]|exports|deps) [--json]")
    end
  end

  defp callers(target) do
    {out, _} = System.cmd("mix", ["xref", "callers", target], stderr_to_stdout: true)
    out |> String.split("\n") |> Enum.filter(&String.contains?(&1, "(")) |> Enum.map(&String.trim/1)
  end

  # The boundary's export list, as module names — what `Server` promises a consumer.
  defp exports do
    Mix.Task.run("compile", ["--no-deps-check"])
    exports = :attributes |> Server.__info__() |> Keyword.get(:boundary_exports, [])

    if exports == [],
      do: boundary_exports_from_source(),
      else: Enum.map(exports, &inspect/1)
  end

  defp boundary_exports_from_source do
    {:ok, ast} = Sourceror.parse_string(File.read!("lib/server.ex"))

    ast
    |> Sourceror.Zipper.zip()
    |> Sourceror.Zipper.traverse([], fn z, acc ->
      case Sourceror.Zipper.node(z) do
        {:use, _, [{:__aliases__, _, [:Boundary]}, opts]} -> {z, acc ++ export_names(opts)}
        _ -> {z, acc}
      end
    end)
    |> elem(1)
  end

  defp export_names(opts) do
    case Enum.find(opts, fn {{:__block__, _, [k]}, _} -> k == :exports end) do
      {_, {:__block__, _, [list]}} when is_list(list) ->
        Enum.map(list, &(&1 |> Sourceror.to_string() |> String.split("\n") |> List.last()))

      _ ->
        []
    end
  end

  defp deps do
    {outdated, _} = System.cmd("mix", ["hex.outdated"], stderr_to_stdout: true)
    {audit, _} = System.cmd("mix", ["hex.audit"], stderr_to_stdout: true)

    %{
      outdated: outdated |> String.split("\n") |> Enum.filter(&Regex.match?(~r/^\S+\s+\d/, &1)),
      advisories: audit |> String.split("\n") |> Enum.filter(&String.contains?(&1, "vulnerab"))
    }
  end

  defp emit(true, data, _lines), do: Mix.shell().info(JSON.encode!(data))
  defp emit(false, data, lines), do: data |> lines.() |> Enum.each(fn line -> Mix.shell().info(line) end)
end
