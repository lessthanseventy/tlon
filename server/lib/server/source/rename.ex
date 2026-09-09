defmodule Server.Source.Rename do
  @moduledoc """
  Rename an identifier in Elixir source by walking its AST (Sourceror), so a rename lands on
  every def/defp head, call, capture and variable and never on a string or a comment. The file is
  PATCHED, not reprinted: each matched node's source range is replaced in place, so every other
  byte — comments, blank lines, the project's own formatting — is untouched. `atoms: true` also
  renames the bare atom `:old` and the keyword/map key `old:`. The operator's door is
  `mix ast.rename`; a coworker's is the same function behind an MCP verb.
  """

  alias Sourceror.Zipper

  @spec run(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, term()}
  def run(source, old, new, opts \\ []) when is_binary(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> apply_patches(source, patches(ast, String.to_atom(old), new, Keyword.get(opts, :atoms, false)))
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_patches(source, []), do: source
  defp apply_patches(source, patches), do: Sourceror.patch_string(source, patches)

  defp patches(ast, from, new, atoms?) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc ->
      case patch_for(Zipper.node(z), from, new, atoms?) do
        nil -> {z, acc}
        patch -> {z, [patch | acc]}
      end
    end)
    |> elem(1)
  end

  # A local call / def head / variable: `{name, meta, args_or_context}` — the identifier is the
  # first `String.length(old)` bytes of the node's range.
  defp patch_for({from, _meta, args} = node, from, new, _atoms?) when is_list(args) or is_atom(args),
    do: ident_patch(node, from, new)

  # A bare atom or a keyword key is a literal Sourceror wraps: `{:__block__, meta, [:old]}`.
  # `:old` → `:new`; the key form `old:` → `new:` (Sourceror marks it `format: :keyword`).
  defp patch_for({:__block__, meta, [from]} = node, from, new, true) do
    case Sourceror.get_range(node) do
      nil -> nil
      range -> %{range: range, change: if(meta[:format] == :keyword, do: "#{new}:", else: ":#{new}")}
    end
  end

  defp patch_for(_node, _from, _new, _atoms?), do: nil

  defp ident_patch(node, from, new) do
    case Sourceror.get_range(node) do
      %{start: [line: l, column: c]} ->
        len = String.length(Atom.to_string(from))
        %{range: %{start: [line: l, column: c], end: [line: l, column: c + len]}, change: new}

      _ ->
        nil
    end
  end
end
