defmodule Console.Panel.MenuTest do
  @moduledoc "The overlay menu (right-click workspace context menu / icon picker)."
  use ExUnit.Case, async: true

  import Console.PanelText, only: [row_text: 1]

  alias Console.Panel.Menu

  @data %{
    title: "ws",
    cursor: 1,
    items: [
      %{label: "Set icon…", action: {:icon_picker, %{id: 1}}},
      %{label: "Configure", action: {:configure_ws, %{id: 1}}},
      %{label: "Delete", action: {:delete_ws, %{id: 1}}, danger: true}
    ]
  }

  test "render lists the items, marks the cursor row" do
    rows = Menu.render(@data, %{x: 0, y: 0, w: 20, h: 5})
    lines = Enum.map(rows, &row_text/1)

    assert Enum.at(lines, 0) =~ "Set icon"
    assert Enum.at(lines, 1) =~ "▸" and Enum.at(lines, 1) =~ "Configure"
    assert Enum.at(lines, 2) =~ "Delete"
  end

  test "pick returns the row's action as {:menu_pick, action}" do
    assert {:menu_pick, {:icon_picker, %{id: 1}}} = Menu.pick(@data, %{x: 0, y: 0, w: 20, h: 5}, 0)
    assert {:menu_pick, {:delete_ws, %{id: 1}}} = Menu.pick(@data, %{x: 0, y: 0, w: 20, h: 5}, 2)
    assert Menu.pick(@data, %{x: 0, y: 0, w: 20, h: 5}, 9) == nil
  end

  test "width is the widest row (lead + label)" do
    assert Menu.width(@data) == String.length("Set icon…") + 2
  end

  test "more items than rows: the list scrolls so the cursor row is on screen, and pick follows" do
    rect = %{x: 0, y: 0, w: 20, h: 2}
    data = %{@data | cursor: 2}
    lines = data |> Menu.render(rect) |> Enum.map(&row_text/1)

    assert length(lines) == 2
    assert Enum.at(lines, 0) =~ "Configure"
    assert Enum.at(lines, 1) =~ "▸" and Enum.at(lines, 1) =~ "Delete"
    assert {:menu_pick, {:delete_ws, _}} = Menu.pick(data, rect, 1)
  end
end
