defmodule Server.Source.Outline do
  @moduledoc """
  A source file as data: every module (nested ones under `modules`) with its moduledoc's first
  line, the lines it spans, and its defs — name, arity, kind (`def`/`defp`/`defmacro`/…), the
  `@doc` first line and `@spec` text that precede it, and the lines the clause spans. What an
  agent reads before it edits; the outline door is `mix ast.outline FILE`.
  """

  @kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  @spec run(String.t()) :: {:ok, [map()]} | {:error, term()}
  def run(source) when is_binary(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, modules(ast)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Top-level modules; a `defmodule` nested in a body lands under its parent's `modules`, with
  # the full name Elixir gives it (`Parent.Inner`).
  defp modules(ast, parent \\ nil)
  defp modules({:__block__, _, forms}, parent), do: Enum.flat_map(forms, &modules(&1, parent))
  defp modules({:defmodule, _, [name, [{_do, body}]]} = node, parent), do: [module(full_name(name, parent), body, node)]
  defp modules(_other, _parent), do: []

  defp full_name(name, nil), do: Macro.to_string(name)
  defp full_name(name, parent), do: parent <> "." <> Macro.to_string(name)

  defp module(name, body, node) do
    forms = body_forms(body)

    %{
      module: name,
      doc: attr_first_line(forms, :moduledoc),
      lines: lines(node),
      defs: defs(forms),
      modules: Enum.flat_map(forms, &modules(&1, name))
    }
  end

  defp body_forms({:__block__, _, forms}), do: forms
  defp body_forms(form), do: [form]

  # Walk the body keeping the @doc/@spec that precede each def; a def consumes them.
  defp defs(forms) do
    forms
    |> Enum.reduce({[], nil, nil}, fn form, {acc, doc, spec} ->
      case form do
        {:@, _, [{:doc, _, [text]}]} -> {acc, string_first_line(text), spec}
        {:@, _, [{:spec, _, [expr]}]} -> {acc, doc, Sourceror.to_string(expr)}
        {kind, _, [head | _]} = node when kind in @kinds -> {[def_entry(kind, head, doc, spec, node) | acc], nil, nil}
        _ -> {acc, doc, spec}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp def_entry(kind, head, doc, spec, node) do
    {name, arity} = name_arity(head)
    %{name: name, arity: arity, kind: kind, doc: doc, spec: spec, lines: lines(node)}
  end

  # `def name(args) when guard` → the guarded head's inner call; `def name` (no parens) → arity 0.
  defp name_arity({:when, _, [head | _]}), do: name_arity(head)
  defp name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp name_arity({name, _, _}), do: {name, 0}

  defp attr_first_line(forms, attr) do
    Enum.find_value(forms, fn
      {:@, _, [{^attr, _, [text]}]} -> string_first_line(text)
      _ -> nil
    end)
  end

  # A doc is a string literal Sourceror wraps in a `:__block__`; `false` (no doc) reads as nil.
  defp string_first_line({:__block__, _, [text]}) when is_binary(text), do: text |> String.split("\n") |> hd()
  defp string_first_line(_other), do: nil

  defp lines(node) do
    case Sourceror.get_range(node) do
      %{start: [line: a, column: _], end: [line: b, column: _]} -> {a, b}
      _ -> nil
    end
  end
end
