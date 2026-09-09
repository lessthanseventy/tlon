defmodule Server.Source.Clause do
  @moduledoc """
  The clause verbs: address one clause of `name/arity` by its head as written — the args, and the
  guard if any (`":b"`, `"x when is_integer(x)"`) — then replace its body, delete it, or insert a
  new clause right after it. Patches from the clause's own source range (Sourceror), so the rest
  of the file is byte-identical. A miss names the clauses that exist. Whitespace in the head
  pattern is ignored.
  """

  alias Sourceror.Zipper

  @kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp]

  @doc "Replace the clause's body with `code` (one line → `, do:` form; more → a `do … end` block)."
  @spec replace_body(String.t(), String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  def replace_body(source, name_arity, head, code) do
    with {:ok, clause} <- find(source, name_arity, head) do
      Sourceror.patch_string(source, [
        %{range: clause.range, change: clause_text(clause, code), preserve_indentation: false}
      ])
    end
  end

  @doc "Delete the clause, the comment lines glued above it, and one blank line left behind."
  @spec delete(String.t(), String.t(), String.t(), keyword()) :: String.t() | {:error, String.t()}
  def delete(source, name_arity, head, _opts \\ []) do
    with {:ok, %{range: %{start: [line: a, column: _], end: [line: b, column: _]}}} <- find(source, name_arity, head) do
      lines = String.split(source, "\n")
      first = a - 1 - comment_lines_above(lines, a - 1)
      last = b - 1

      last =
        if Enum.at(lines, last + 1) == "" and (first == 0 or Enum.at(lines, first - 1) == ""),
          do: last + 1,
          else: last

      lines
      |> Enum.with_index()
      |> Enum.reject(fn {_l, i} -> i >= first and i <= last end)
      |> Enum.map_join("\n", &elem(&1, 0))
    end
  end

  @doc "Insert `code` as a new clause on the line after the addressed one, at its indent."
  @spec insert_after(String.t(), String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  def insert_after(source, name_arity, head, code) do
    with {:ok, %{range: %{end: [line: b, column: c]}, indent: indent}} <- find(source, name_arity, head) do
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: b, column: c], end: [line: b, column: c]}
      Sourceror.patch_string(source, [%{range: at, change: "\n" <> body, preserve_indentation: false}])
    end
  end

  @doc "Insert `code` as a new clause on the line before the addressed one, at its indent."
  @spec insert_before(String.t(), String.t(), String.t(), String.t()) :: String.t() | {:error, String.t()}
  def insert_before(source, name_arity, head, code) do
    with {:ok, %{range: %{start: [line: a, column: _]}, indent: indent}} <- find(source, name_arity, head) do
      body = code |> String.split("\n") |> Enum.map_join("\n", &(indent <> &1))
      at = %{start: [line: a, column: 1], end: [line: a, column: 1]}
      Sourceror.patch_string(source, [%{range: at, change: body <> "\n", preserve_indentation: false}])
    end
  end

  # -- locating a clause ----------------------------------------------------

  defp find(source, name_arity, head) do
    with {:ok, {name, arity}} <- parse_name_arity(name_arity),
         {:ok, ast} <- parse(source) do
      clauses = clauses(ast, name, arity)
      want = squash(head)

      case Enum.find(clauses, &(squash(&1.head_text) == want)) do
        nil -> {:error, "no clause #{name}/#{arity} with head `#{head}` — have: #{heads(clauses)}"}
        clause -> {:ok, clause}
      end
    end
  end

  defp parse(source) do
    case Sourceror.parse_string(source) do
      {:ok, ast} -> {:ok, ast}
      {:error, reason} -> {:error, "not parseable — #{inspect(reason)}"}
    end
  end

  defp parse_name_arity(spec) do
    case String.split(spec, "/") do
      [name, arity] -> {:ok, {String.to_atom(name), String.to_integer(arity)}}
      _ -> {:error, "expected name/arity, got #{inspect(spec)}"}
    end
  end

  defp clauses(ast, name, arity) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse([], fn z, acc -> {z, acc ++ matching(Zipper.node(z), name, arity)} end)
    |> elem(1)
  end

  defp matching({kind, _meta, [head | _]} = node, name, arity) when kind in @kinds do
    if name_arity(head) == {name, arity}, do: [clause(kind, name, head, node)], else: []
  end

  defp matching(_node, _name, _arity), do: []

  defp clause(kind, name, head, node) do
    %{start: [line: _, column: col]} = range = Sourceror.get_range(node)
    {args, guard} = split_head(head)

    %{
      kind: kind,
      name: name,
      args: args,
      guard: guard,
      head_text: if(guard, do: args <> " when " <> guard, else: args),
      range: range,
      indent: String.duplicate(" ", col - 1)
    }
  end

  defp name_arity({:when, _, [call | _]}), do: name_arity(call)
  defp name_arity({name, _, args}) when is_list(args), do: {name, length(args)}
  defp name_arity({name, _, _}), do: {name, 0}

  # The head as written: `{args_text, guard_text | nil}`.
  defp split_head({:when, _, [call, guard]}), do: {elem(split_head(call), 0), Sourceror.to_string(guard)}
  defp split_head({_name, _, args}) when is_list(args), do: {Enum.map_join(args, ", ", &Sourceror.to_string/1), nil}
  defp split_head(_head), do: {"", nil}

  defp squash(text), do: String.replace(text, ~r/\s+/, "")
  defp heads([]), do: "none"
  defp heads(clauses), do: Enum.map_join(clauses, " · ", &"`#{&1.head_text}`")

  # -- text -----------------------------------------------------------------

  defp clause_text(%{kind: kind, name: name, args: args, guard: guard, indent: indent}, code) do
    head = "#{kind} #{name}(#{args})" <> if(guard, do: " when " <> guard, else: "")

    case String.split(String.trim(code), "\n") do
      [one] -> head <> ", do: " <> one
      many -> head <> " do\n" <> Enum.map_join(many, "\n", &(indent <> "  " <> &1)) <> "\n" <> indent <> "end"
    end
  end

  defp comment_lines_above(lines, i) do
    lines
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.take_while(&String.starts_with?(String.trim_leading(&1), "#"))
    |> length()
  end
end
