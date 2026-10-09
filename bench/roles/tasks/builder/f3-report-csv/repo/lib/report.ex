defmodule Report do
  @moduledoc "The nightly check report: one row per check — name, runs, pass ratio."

  @doc "The report for `rows` (maps with `:name`, `:runs`, `:ratio`) as a text table."
  def render(rows) do
    lines = [header()] ++ Enum.map(rows, &row/1) ++ [total(rows)]
    Enum.join(lines, "\n") <> "\n"
  end

  defp header do
    String.pad_trailing("check", 12) <> String.pad_leading("runs", 6) <> String.pad_leading("pass", 7)
  end

  defp row(r) do
    String.pad_trailing(r.name, 12) <>
      String.pad_leading(Integer.to_string(r.runs), 6) <>
      String.pad_leading(:erlang.float_to_binary(r.ratio * 1.0, decimals: 2), 7)
  end

  defp total(rows) do
    runs = rows |> Enum.map(& &1.runs) |> Enum.sum()
    String.pad_trailing("total", 12) <> String.pad_leading(Integer.to_string(runs), 6)
  end
end
