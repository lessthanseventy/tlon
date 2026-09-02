defmodule Console.PasteBufferTest do
  @moduledoc """
  The bracketed-paste buffer state machine (pure — the cockpit holds the buffer in its state, this
  module owns the transitions). On paste-start the cockpit starts a buffer; while pasting, content
  keys accumulate here (a newline stays \\n, NOT :enter); on paste-end the whole buffer is forwarded
  to the center terminal wrapped back in the markers. A regression here means a paste lands as N
  submits instead of one block.
  """
  use ExUnit.Case, async: true

  alias Console.PasteBuffer

  test "start → accumulate chars and newlines → finish wraps in the markers" do
    buffer =
      PasteBuffer.start()
      |> PasteBuffer.accumulate(%{key: :char, char: "h"})
      |> PasteBuffer.accumulate(%{key: :char, char: "i"})
      |> PasteBuffer.accumulate(%{key: :enter})
      |> PasteBuffer.accumulate(%{key: :char, char: "x"})

    assert PasteBuffer.finish(buffer) == "\e[200~hi\nx\e[201~"
  end

  test "a newline accumulates as \\n, not :enter" do
    assert PasteBuffer.accumulate(PasteBuffer.start(), %{key: :enter}) == "\n"
  end

  test "a tab accumulates as \\t" do
    assert PasteBuffer.accumulate(PasteBuffer.start(), %{key: :tab}) == "\t"
  end

  test "a space accumulates as a space" do
    assert PasteBuffer.accumulate(PasteBuffer.start(), %{key: :space}) == " "
  end

  test "non-content keys (arrows, modifiers) are skipped, not leaked into the buffer" do
    buffer =
      PasteBuffer.start()
      |> PasteBuffer.accumulate(%{key: :up})
      |> PasteBuffer.accumulate(%{key: :char, char: "a", ctrl: true})

    assert buffer == ""
  end

  test "an empty paste finishes as just the two markers" do
    assert PasteBuffer.finish(PasteBuffer.start()) == "\e[200~\e[201~"
  end
end
