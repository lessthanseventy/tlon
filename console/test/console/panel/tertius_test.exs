defmodule Console.Panel.TertiusTest do
  # The permanent tertius command line band (Slice 3): input line + recent receipts. Pure render.
  use ExUnit.Case, async: true

  import Console.PanelText, only: [text: 1]

  alias Console.Panel.Tertius

  defp rect, do: %{x: 0, y: 0, w: 80, h: 6}

  test "idle: a permanent tertius prompt with a placeholder" do
    out = %{receipts: [], input: nil} |> Tertius.render(rect()) |> text()
    assert out =~ "tertius ▸"
    assert out =~ "file a ticket"
  end

  test "active: renders the live buffer with a caret" do
    out = %{receipts: [], input: %{kind: :orchestrate, buffer: "file a ticket x"}} |> Tertius.render(rect()) |> text()
    assert out =~ "tertius ▸ file a ticket x"
    assert out =~ "▎"
  end

  test "shows the last couple of receipts above the input, oldest-first" do
    out = %{receipts: ["→ noted #2 ✓", "→ filed ticket #1 ✓"], input: nil} |> Tertius.render(rect()) |> text()
    # newest is head of the list; the log shows the last two in chronological order (oldest first)
    lines = String.split(out, "\n")
    assert Enum.at(lines, 0) =~ "filed ticket #1"
    assert Enum.at(lines, 1) =~ "noted #2"
    assert List.last(lines) =~ "tertius ▸"
  end
end
