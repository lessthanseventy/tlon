defmodule Console.PanelText do
  @moduledoc """
  Row-flattening helpers for the panel suites. A panel renders `[[{text, style}]]`; an assertion
  almost always wants the text, so this is the one place that drops the styles.
  """

  @doc "The text of one styled row, styles dropped."
  @spec row_text(Console.Panel.row()) :: String.t()
  def row_text(row), do: Enum.map_join(row, fn {t, _s} -> t end)

  @doc "Rows flattened to one newline-joined string."
  @spec text([Console.Panel.row()]) :: String.t()
  def text(rows), do: Enum.map_join(rows, "\n", &row_text/1)

  @doc "Rows as a list of their texts, one string per row."
  @spec lines([Console.Panel.row()]) :: [String.t()]
  def lines(rows), do: Enum.map(rows, &row_text/1)
end
