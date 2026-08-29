defmodule Console.Panel.BorderTest do
  @moduledoc """
  The on-frame section label (design 2026-08-23): digit-first titles, the carousel tab strip,
  the bottom-corner hint — and tab_at_x/2 agreeing with what render/2 draws.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Border

  defp rect(w \\ 20, h \\ 5), do: %{x: 0, y: 0, w: w, h: h}

  defp row_text(row), do: Enum.map_join(row, fn {t, _s} -> t end)

  test "a plain border (no title) renders the bare frame" do
    [top | _] = Border.render(%{focused: false}, rect())
    assert row_text(top) == "╭" <> String.duplicate("─", 18) <> "╮"
  end

  test "title + digit are punched into the top rule, digit first" do
    [top | _] = Border.render(%{focused: false, digit: 2, title: "STACK"}, rect())
    assert row_text(top) =~ "╭─ 2 STACK ─"
    assert String.length(row_text(top)) == 20
  end

  test "the focused frame is heavy and the title rides it" do
    [top | _] = Border.render(%{focused: true, digit: 2, title: "STACK"}, rect())
    assert row_text(top) =~ "╔═ 2 STACK ═"
  end

  test "a title too wide for the box is dropped, keeping the corners" do
    [top | _] = Border.render(%{focused: false, digit: 1, title: "MUCHTOOLONG"}, rect(8))
    assert row_text(top) == "╭──────╮"
  end

  test "tabs render as a strip — active lit (:header), siblings dim" do
    data = %{focused: false, digit: 5, tabs: [{"CREW", true}, {"ACT", false}]}
    [top | _] = Border.render(data, rect(30))
    assert row_text(top) =~ " 5 CREW · ACT "
    assert {"CREW", :header} in top
    assert {"ACT", :dim} in top
  end

  test "a hint renders right-aligned on the bottom rule" do
    rows = Border.render(%{focused: false, hint: "[ ] cycle"}, rect(20))
    bottom = List.last(rows)
    assert row_text(bottom) =~ "[ ] cycle ─╯" == false
    assert row_text(bottom) =~ " [ ] cycle "
    assert String.ends_with?(row_text(bottom), "╯")
    assert String.length(row_text(bottom)) == 20
  end

  test "tab_at_x maps a top-row x to the tab index render drew there" do
    data = %{focused: false, digit: 5, tabs: [{"CREW", true}, {"ACTIVITY", false}, {"LEAVES", false}]}
    [top | _] = Border.render(data, rect(40))
    text = row_text(top)

    for {label, i} <- Enum.with_index(["CREW", "ACTIVITY", "LEAVES"]) do
      # grapheme offset of the label's first char in the top row (unique per label here).
      gx = text |> String.graphemes() |> Enum.take_while(&(&1 != String.first(label))) |> length()
      assert Border.tab_at_x(data, gx) == i
    end

    assert Border.tab_at_x(data, 0) == nil
  end

  test "nil data still renders the plain thin frame (legacy callers)" do
    [top | _] = Border.render(nil, rect())
    assert row_text(top) =~ "╭"
  end
end
