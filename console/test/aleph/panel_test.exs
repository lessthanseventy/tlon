# A panel that declares image placements, for probing Panel.images/3's dispatch.
defmodule ImagesProbe do
  @moduledoc false
  @behaviour Console.Panel

  @impl true
  def topics(_assigns), do: []
  @impl true
  def render(_data, _rect), do: []
  @impl true
  def images(data, rect), do: [%{id: 1, data: data, rect: rect}]
end

defmodule Console.PanelTest do
  @moduledoc """
  The `images/2` seam (design 2026-08-23 §Images, slice 7): a panel opts in with an optional
  callback; `Panel.images/3` dispatches to it (or [] when absent), mirroring `Panel.hints/2`.
  """
  use ExUnit.Case, async: true

  alias Console.Panel

  test "a panel without images/2 declares no placements" do
    assert Panel.images(Console.Panel.Health, %{}, %{x: 0, y: 0, w: 10, h: 10}) == []
  end

  test "a panel with images/2 has its placements dispatched through" do
    rect = %{x: 0, y: 0, w: 10, h: 10}
    assert Panel.images(ImagesProbe, :data, rect) == [%{id: 1, data: :data, rect: rect}]
  end
end
