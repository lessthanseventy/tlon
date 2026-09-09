defmodule Server.Source.Tools do
  @moduledoc """
  The coworkers' source verbs, scoped to the calling thread's worktree: every path is resolved
  under `Server.worktree_for_thread/1` and a path that escapes it is refused — an agent edits its
  own tree and nothing else. Pure over the thread + paths; `Server.MCP.Tool.RenameIdentifier` /
  `OutlineFile` are thin callers. Renames are `Server.Source.Rename` patches (only the identifier
  moves); outlines are `Server.Source.Outline`.
  """

  alias Server.Source.Outline
  alias Server.Source.Rename

  @spec rename(Server.Thread.t(), [String.t()], String.t(), String.t(), keyword()) ::
          {:ok, %{changed: [String.t()], unchanged: [String.t()]}} | {:error, String.t()}
  def rename(thread, files, old, new, opts) do
    with {:ok, root} <- root(thread),
         {:ok, paths} <- resolve_all(root, files) do
      {changed, unchanged} =
        Enum.split_with(paths, fn {_rel, abs} -> rewrite(abs, old, new, opts) end)

      {:ok, %{changed: Enum.map(changed, &elem(&1, 0)), unchanged: Enum.map(unchanged, &elem(&1, 0))}}
    end
  end

  @spec outline(Server.Thread.t(), String.t()) :: {:ok, %{file: String.t(), modules: [map()]}} | {:error, String.t()}
  def outline(thread, file) do
    with {:ok, root} <- root(thread),
         {:ok, [{rel, abs}]} <- resolve_all(root, [file]),
         {:ok, source} <- read(abs),
         {:ok, modules} <- parsed(Outline.run(source), rel) do
      {:ok, %{file: rel, modules: modules}}
    end
  end

  defp root(thread) do
    case Server.worktree_for_thread(thread) do
      {:ok, root} -> {:ok, root}
      {:error, :no_repo} -> {:error, "no repo: this thread's workspace has no repo-bearing project"}
      {:error, reason} -> {:error, "no worktree: #{inspect(reason)}"}
    end
  end

  # Every path lands inside `root` or the whole call is refused — no partial edits.
  defp resolve_all(root, files) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      abs = Path.expand(file, root)

      if String.starts_with?(abs, root <> "/"),
        do: {:cont, {:ok, acc ++ [{Path.relative_to(abs, root), abs}]}},
        else: {:halt, {:error, "refused: #{file} is outside the thread's worktree"}}
    end)
  end

  defp read(abs) do
    case File.read(abs) do
      {:ok, source} -> {:ok, source}
      {:error, reason} -> {:error, "#{abs}: #{:file.format_error(reason)}"}
    end
  end

  defp parsed({:ok, modules}, _rel), do: {:ok, modules}
  defp parsed({:error, reason}, rel), do: {:error, "#{rel}: not parseable — #{inspect(reason)}"}

  defp rewrite(abs, old, new, opts) do
    with {:ok, source} <- File.read(abs),
         out when is_binary(out) and out != source <- Rename.run(source, old, new, opts) do
      File.write!(abs, out)
      true
    else
      _ -> false
    end
  end
end
