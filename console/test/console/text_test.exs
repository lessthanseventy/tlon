defmodule Console.TextTest do
  # wrap_paragraphs: hard newlines keep their breaks, blank-line runs collapse to ONE empty
  # line between paragraphs — the message-readability seam both chat renderers share.
  use ExUnit.Case, async: true

  alias Console.Text

  doctest Console.Text

  describe "wrap_paragraphs/2" do
    test "a blank line separates paragraphs with exactly one empty line" do
      assert Text.wrap_paragraphs("first para\n\nsecond para", 40) ==
               ["first para", "", "second para"]
    end

    test "a run of blank lines still yields one separator" do
      assert Text.wrap_paragraphs("a\n\n\n\nb", 40) == ["a", "", "b"]
    end

    test "single newlines keep their breaks — a list survives" do
      assert Text.wrap_paragraphs("- one\n- two", 40) == ["- one", "- two"]
    end

    test "each paragraph wraps to the width" do
      assert Text.wrap_paragraphs("alpha beta gamma\n\ndelta", 10) ==
               ["alpha beta", "gamma", "", "delta"]
    end

    test "an empty string yields no rows" do
      assert Text.wrap_paragraphs("", 40) == []
    end
  end

  # An INPUT buffer is not prose: what you typed is what you see. `wrap/2` collapses whitespace,
  # so a trailing space (or a double space) vanished from the reply box until the next word
  # arrived (Andrew, 2026-09-08: "spaces would go through but not display"). `wrap_exact/2` keeps
  # every character: the lines re-join to the input, spaces included.
  describe "wrap_exact/2" do
    test "a trailing space is kept on the line" do
      assert Text.wrap_exact("hello ", 20) == ["hello "]
    end

    test "double spaces survive" do
      assert Text.wrap_exact("a  b", 20) == ["a  b"]
    end

    test "lines re-join to the input exactly, breaking after a space when one is in reach" do
      text = "one two three four"
      lines = Text.wrap_exact(text, 9)
      assert lines == ["one two ", "three ", "four"]
      assert Enum.join(lines) == text
    end

    test "a word longer than the width hard-breaks and still re-joins" do
      text = "abcdefghij kl"
      lines = Text.wrap_exact(text, 4)
      assert Enum.join(lines) == text
      assert Enum.all?(lines, &(String.length(&1) <= 4))
    end

    test "the empty string is one empty line, so the caret has a row" do
      assert Text.wrap_exact("", 10) == [""]
    end
  end
end
