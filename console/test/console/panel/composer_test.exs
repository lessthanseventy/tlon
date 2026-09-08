defmodule Console.Panel.ComposerTest do
  # The growable compose box: full buffer wrapped (never truncated), the ▎ cursor on its actual
  # line/col, and a window that scrolls to keep the cursor visible past the height cap.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.Composer

  describe "lines/2 — the wrapped buffer with the cursor marker" do
    test "an empty buffer is one line holding just the cursor" do
      assert Composer.lines(%{buffer: "", cursor: 0}, 40) == ["▎"]
    end

    test "hard newlines split lines; blank lines survive" do
      assert ["one▎", "", "two"] = Composer.lines(%{buffer: "one\n\ntwo", cursor: 3}, 40)
    end

    test "a long line wraps to the width instead of truncating" do
      buffer = "alpha beta gamma delta epsilon"
      lines = Composer.lines(%{buffer: buffer, cursor: String.length(buffer)}, 12)
      assert length(lines) > 1
      assert Enum.all?(lines, &(String.length(&1) <= 12))
      assert List.last(lines) =~ "▎"
    end

    test "the marker sits at the cursor's actual position, not the end" do
      assert ["ab▎cd"] = Composer.lines(%{buffer: "abcd", cursor: 2}, 40)
    end
  end

  describe "render/2" do
    test "renders every buffer line with the prompt gutter on the first row" do
      rows = Composer.render(%{input: %{buffer: "one\ntwo", cursor: 7}}, %{x: 0, y: 0, w: 40, h: 5})
      assert text(rows) =~ "▸ one"
      assert text(rows) =~ "two▎"
    end

    test "the cursor marker renders as its own accent run" do
      rows = Composer.render(%{input: %{buffer: "ab", cursor: 1}}, %{x: 0, y: 0, w: 40, h: 2})
      assert [first | _] = rows
      assert {"▎", :accent} in first
    end

    test "past the height cap the window scrolls to keep the cursor line visible" do
      buffer = Enum.map_join(1..10, "\n", &"line#{&1}")
      rows = Composer.render(%{input: %{buffer: buffer, cursor: String.length(buffer)}}, %{x: 0, y: 0, w: 40, h: 3})
      assert length(rows) == 3
      assert text(rows) =~ "line10▎"
      refute text(rows) =~ "line1\n"
    end
  end
end
