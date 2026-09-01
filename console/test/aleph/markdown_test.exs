defmodule Console.MarkdownTest do
  use ExUnit.Case, async: true

  alias Console.Markdown

  defp text(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _} -> t end) end)
  defp styles(rows), do: rows |> Enum.flat_map(& &1) |> Enum.map(fn {_t, s} -> s end)

  test "inline bold/code become styled runs; surrounding text keeps the base style" do
    rows = Markdown.render("a **bold** and `code` word", 80, :normal)
    runs = List.first(rows)

    assert {"bold", :md_bold} in runs
    assert {"code", :md_code} in runs
    assert Enum.any?(runs, fn {t, s} -> t =~ "a " and s == :normal end)
  end

  test "a heading renders in the heading style, hashes stripped" do
    [row] = Markdown.render("## Who I am", 80)
    assert [{"Who I am", :md_head}] = row
  end

  test "bullet lists get a marker + inline-parsed body" do
    rows = Markdown.render("- first\n- **second**", 80)
    lines = text(rows)
    assert Enum.any?(lines, &(&1 =~ "• first"))
    assert Enum.any?(lines, &(&1 =~ "• second"))
    assert :md_bold in styles(rows)
  end

  test "fenced code blocks render verbatim in the code style, no inline parsing" do
    rows = Markdown.render("```\nx = **not bold**\n```", 80)
    joined = text(rows) |> Enum.join("\n")
    assert joined =~ "x = **not bold**"
    assert :md_code in styles(rows)
    refute :md_bold in styles(rows)
  end

  test "long text wraps to width" do
    rows = Markdown.render(String.duplicate("word ", 40), 30)
    assert length(rows) > 1
    assert Enum.all?(rows, fn row -> row |> Enum.map_join(fn {t, _} -> t end) |> String.length() <= 30 end)
  end

  test "blank lines separate paragraphs" do
    rows = Markdown.render("one\n\ntwo", 80)
    assert text(rows) == ["one", "", "two"]
  end
end
