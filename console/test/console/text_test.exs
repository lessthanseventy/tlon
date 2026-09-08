defmodule Console.TextTest do
  # wrap_paragraphs: hard newlines keep their breaks, blank-line runs collapse to ONE empty
  # line between paragraphs — the message-readability seam both chat renderers share.
  use ExUnit.Case, async: true

  alias Console.Text

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

  describe "duration/1" do
    test "under a minute is bare seconds" do
      assert Text.duration(0) == "0s"
      assert Text.duration(45) == "45s"
      assert Text.duration(59) == "59s"
    end

    test "a minute or more is Mm Ss" do
      assert Text.duration(60) == "1m0s"
      assert Text.duration(72) == "1m12s"
      assert Text.duration(3599) == "59m59s"
    end

    test "an hour or more drops seconds — Hh Mm" do
      assert Text.duration(3600) == "1h0m"
      assert Text.duration(3900) == "1h5m"
      assert Text.duration(7_384) == "2h3m"
    end

    test "negative (clock skew) clamps to 0s rather than reading backwards" do
      assert Text.duration(-5) == "0s"
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
