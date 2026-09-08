defmodule Console.Panel.TopBarTest do
  @moduledoc """
  The frame's top line (UX slice 1): where am I, what am I on, who is on it, is the server up.
  """
  use ExUnit.Case, async: true

  import Console.PanelText, only: [row_text: 1]

  alias Console.Panel.TopBar

  test "one row: workspace · thread and stage · coworker and warmth · link" do
    data = %{workspace: "Tlön", thread: "review PR 42", stage: "build", lead: "hronir", warm?: true, link: :up}
    [row] = TopBar.render(data, %{x: 0, y: 0, w: 80, h: 1})
    text = row_text(row)

    assert text =~ "Tlön"
    assert text =~ "review PR 42"
    assert text =~ "build"
    assert text =~ "hronir"
    assert text =~ "●"
  end

  test "a cold coworker gets the hollow dot" do
    data = %{workspace: "Tlön", thread: "t", lead: "hronir", warm?: false, link: :up}
    [row] = TopBar.render(data, %{x: 0, y: 0, w: 80, h: 1})
    assert row_text(row) =~ "○ hronir"
  end

  test "a down link is named, and nothing crashes on an empty workspace" do
    [row] = TopBar.render(%{link: :down}, %{x: 0, y: 0, w: 40, h: 1})
    assert row_text(row) =~ "server down"
  end

  test "no thread, no stage, no lead — one row, no stray separators" do
    [row] = TopBar.render(%{workspace: "Tlön", link: :up}, %{x: 0, y: 0, w: 60, h: 1})
    text = row_text(row)

    assert text =~ "Tlön"
    refute text =~ "·"
  end

  test "the row is exactly one line, clipped to the rect width" do
    data = %{workspace: String.duplicate("w", 50), thread: String.duplicate("t", 50), lead: "x", warm?: true, link: :up}
    assert [row] = TopBar.render(data, %{x: 0, y: 0, w: 30, h: 1})
    assert Console.Panel.row_width(row) <= 30
  end
end
