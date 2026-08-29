defmodule Console.Panel.DetailTest do
  # MAIN's detail view: a dumb printer of the cockpit's resolved %{title, lines}. Pins the
  # panel → styled-rows path headlessly; the real paint is the eye test.
  use ExUnit.Case, async: true

  alias Console.Panel.Detail

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp text(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _s} -> t end) end)
  defp styles(rows), do: Enum.flat_map(rows, fn row -> Enum.map(row, fn {_t, s} -> s end) end)

  test "nil data renders a quiet placeholder, no crash" do
    rows = Detail.render(nil, @rect)
    assert text(rows) == ["no detail"]
  end

  test "renders the title, a rule, then the styled lines" do
    data = %{title: "commit abc · fix", lines: [{"+added", :diff_add}, {"-gone", :diff_del}, {"@@ -1 +1 @@", :diff_hunk}]}
    rows = Detail.render(data, @rect)
    joined = text(rows)

    assert List.first(joined) == "commit abc · fix"
    assert "+added" in joined
    assert "-gone" in joined
    assert :diff_add in styles(rows)
    assert :diff_del in styles(rows)
    assert :diff_hunk in styles(rows)
  end

  test "a scroll offset windows the rows from the top" do
    data = %{title: "t", lines: [{"a", :normal}, {"b", :normal}, {"c", :normal}], scroll: 2}
    rows = Detail.render(data, @rect)
    # dropped the title + rule (2 rows); "a"/"b"/"c" begin appearing
    assert "a" in text(rows)
    refute "t" in text(rows)
  end
end
