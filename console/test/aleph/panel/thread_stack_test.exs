defmodule Console.Panel.ThreadStackTest do
  # The cockpit center (Slice 3): a stack of foldable Slack thread cards. Pure render — folded
  # cards are one-line headers, unfolded ones show messages + a reply input.
  use ExUnit.Case, async: true

  alias Console.Panel.ThreadStack

  defp rect(h \\ 40), do: %{x: 0, y: 0, w: 80, h: h}
  defp text(rows), do: Enum.map_join(rows, "\n", fn row -> Enum.map_join(row, fn {t, _} -> t end) end)

  test "an empty stack renders a placeholder" do
    assert ThreadStack.render(%{cards: []}, rect()) |> text() =~ "no threads yet"
  end

  test "a folded card is a single header line (no messages)" do
    card = %{id: 39, title: "build the thing", lead: "kimi", stage: "build", awaiting: nil, folded?: true, active?: false, messages: [%{author: "kimi", body: "hi"}]}
    rows = ThreadStack.render(%{cards: [card]}, rect())

    assert length(rows) == 1
    line = text(rows)
    assert line =~ "▸ #39 build the thing"
    assert line =~ "@kimi"
    assert line =~ "[build]"
    refute line =~ "kimi: hi"
  end

  test "an unfolded card shows its messages and a reply input" do
    card = %{id: 42, title: "review PR", lead: "hronir", stage: "review", awaiting: nil, folded?: false, active?: true, messages: [%{author: "andrew", body: "take a look"}, %{author: "hronir", body: "on it"}]}
    out = ThreadStack.render(%{cards: [card]}, rect()) |> text()

    assert out =~ "▾ #42 review PR"
    assert out =~ "andrew: take a look"
    assert out =~ "hronir: on it"
    assert out =~ "‹reply to #42…›"
  end

  test "an awaiting gate is chipped on the header" do
    card = %{id: 38, title: "merge", lead: "hronir", stage: "review", awaiting: "andrew", folded?: true, active?: false, messages: []}
    assert ThreadStack.render(%{cards: [card]}, rect()) |> text() =~ "⏸ andrew"
  end

  test "multiple cards stack — folded ones stay one line, the unfolded one expands" do
    cards = [
      %{id: 1, title: "a", lead: nil, stage: nil, awaiting: nil, folded?: false, active?: true, messages: [%{author: "x", body: "hello"}]},
      %{id: 2, title: "b", lead: nil, stage: nil, awaiting: nil, folded?: true, active?: false, messages: []}
    ]

    out = ThreadStack.render(%{cards: cards}, rect()) |> text()
    assert out =~ "▾ #1 a"
    assert out =~ "x: hello"
    assert out =~ "▸ #2 b"
  end
end
