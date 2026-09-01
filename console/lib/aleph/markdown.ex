defmodule Console.Markdown do
  @moduledoc """
  A focused markdown → styled-rows renderer for the chat (2026-09-01) — so an agent's reply reads as
  a proper chat message, not a wall of text. Handles the block shapes agents actually emit: ATX
  headings (`#`), bullet/numbered lists, fenced code blocks (```), blockquotes (`>`), thematic
  breaks (`---`), and blank-line paragraph breaks — plus inline `**bold**`, `*italic*`, and `` `code` ``.

  Emphasis maps to COLOUR (the palette has no bold attribute): see `Console.Style`'s `md_*` keys.
  NOT a full CommonMark parser (no tables/nested lists/reference links) — `mdex` is the upgrade path
  if we need those. `base` is the message's own style (author-coloured); markdown styles layer over it.
  """
  alias Console.Panel
  alias Console.Text

  @doc "Render `text` to styled rows wrapped to `width`, over a `base` style (default :normal)."
  def render(text, width, base \\ :normal) do
    text
    |> String.split("\n")
    |> block_rows(width, base, [])
    |> Enum.reverse()
  end

  # Line-by-line, tracking fenced-code state. `acc` is the reversed row list.
  defp block_rows([], _w, _base, acc), do: acc

  defp block_rows(["```" <> _ | rest], w, base, acc), do: code_block(rest, w, base, acc)

  defp block_rows([line | rest], w, base, acc), do: block_rows(rest, w, base, prepend(line_rows(line, w, base), acc))

  # Inside a fence: render each line verbatim in :md_code until the closing fence (or EOF).
  defp code_block([], _w, _base, acc), do: acc
  defp code_block(["```" <> _ | rest], w, base, acc), do: block_rows(rest, w, base, acc)

  defp code_block([line | rest], w, base, acc) do
    row = [{"  " <> line, :md_code}]
    code_block(rest, w, base, prepend([row], acc))
  end

  # A single non-code source line → 0+ styled rows (wrapped, inline-parsed).
  defp line_rows("", _w, _base), do: [Panel.blank()]

  defp line_rows(line, w, base) do
    cond do
      Regex.match?(~r/\A\s*(-{3,}|\*{3,}|_{3,})\s*\z/, line) ->
        [[{String.duplicate("─", max(w, 1)), :md_rule}]]

      match = Regex.run(~r/\A(\#{1,6})\s+(.*)/, line) ->
        [_, _hashes, text] = match
        wrap_inline(text, w, :md_head)

      match = Regex.run(~r/\A(\s*)[-*+]\s+(.*)/, line) ->
        [_, lead, text] = match
        bullet_rows(lead <> "• ", text, w, base)

      match = Regex.run(~r/\A(\s*)(\d+)[.)]\s+(.*)/, line) ->
        [_, lead, num, text] = match
        bullet_rows(lead <> num <> ". ", text, w, base)

      match = Regex.run(~r/\A\s*>\s?(.*)/, line) ->
        [_, text] = match
        quote_rows(text, w)

      true ->
        wrap_inline(line, w, base)
    end
  end

  # A list item: the marker on the first row, continuation wrapped under it in the marker's width.
  defp bullet_rows(marker, text, w, base) do
    indent = String.duplicate(" ", String.length(marker))

    case Text.wrap(text, max(w - String.length(marker), 4)) do
      [] ->
        [[{marker, :md_bold}]]

      [first | rest] ->
        [[{marker, :md_bold} | inline(first, base)] | Enum.map(rest, &[{indent, base} | inline(&1, base)])]
    end
  end

  defp quote_rows(text, w) do
    text
    |> Text.wrap(max(w - 2, 4))
    |> Enum.map(fn l -> [{"│ ", :md_rule} | inline(l, :md_italic)] end)
  end

  # Wrap plain text to width, then inline-parse each wrapped line over `style`.
  defp wrap_inline(text, w, style) do
    case Text.wrap(text, max(w, 1)) do
      [] -> [Panel.blank()]
      lines -> Enum.map(lines, &inline(&1, style))
    end
  end

  @inline ~r/(\*\*.+?\*\*|`[^`]+`|\*[^*\s].*?\*)/

  # Split a line into styled runs on the inline markers, keeping the surrounding text in `base`.
  defp inline(text, base) do
    @inline
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&token(&1, base))
  end

  defp token("**" <> _ = t, _base), do: {strip(t, 2), :md_bold}
  defp token("`" <> _ = t, _base), do: {strip(t, 1), :md_code}
  defp token("*" <> _ = t, _base) when byte_size(t) > 2, do: {strip(t, 1), :md_italic}
  defp token(t, base), do: {t, base}

  defp strip(t, n), do: t |> String.slice(n, max(String.length(t) - 2 * n, 0))

  defp prepend(rows, acc), do: Enum.reduce(rows, acc, fn row, a -> [row | a] end)
end
