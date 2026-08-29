defmodule Console.MachineChat.ComposeTest do
  @moduledoc "The machine-chat compose box grows: full buffer wrapped, cursor pinned visible."
  use ExUnit.Case, async: true

  alias Console.MachineChat.Layout
  alias Console.MachineChat.Loop

  test "compose_lines wraps the full buffer and carries the cursor marker at the tail" do
    lines = Loop.compose_lines("one two three four five six seven", 12)
    assert length(lines) > 1
    assert lines |> List.last() |> String.contains?("▎")
    assert lines |> Enum.join(" ") |> String.starts_with?("one two")
  end

  test "compose_lines on an empty buffer is a single line" do
    assert [_] = Loop.compose_lines("", 12)
  end

  test "composer_rows renders every wrapped line — glyph on the first, indent after" do
    state = %{view: %{intent: :new, input: "one two three four five six seven"}}
    [[], [_rule], first | rest] = Loop.composer_rows(state, 12, 10)

    assert [{"＋ ", :accent} | _] = first
    assert rest != []
    assert Enum.all?(rest, fn [{indent, _} | _] -> indent == "  " end)
  end

  test "composer_rows windows to the box height, keeping the cursor's tail line" do
    state = %{view: %{intent: :new, input: String.duplicate("word ", 30) <> "tail"}}
    rows = Loop.composer_rows(state, 12, 5)

    # spacer + rule + (5 - 2) content rows, the last carrying the cursor
    assert length(rows) == 5
    assert rows |> List.last() |> Enum.map_join(&elem(&1, 0)) |> String.contains?("▎")
  end

  test "layout grows the composer box with content and the center shrinks to match" do
    l = Layout.compute(160, 40, 4)
    assert l.composer.h == 6
    assert l.composer.y + l.composer.h == 40
    assert l.center.y + l.center.h == l.composer.y
  end

  test "layout caps the composer at half the body so the conversation survives" do
    l = Layout.compute(160, 40, 100)
    assert l.composer.h < div(40, 2) + 2
    assert l.center.h >= 1
    assert l.center.y + l.center.h == l.composer.y
  end
end
