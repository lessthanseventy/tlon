defmodule Console.MachineChat.LayoutTest do
  @moduledoc "The Slack-shaped geometry: rails collapse on narrow terminals; the center always wins."
  use ExUnit.Case, async: true

  alias Console.MachineChat.Layout

  test "wide: header + both rails + separators + center + composer, all disjoint and in-bounds" do
    l = Layout.compute(160, 40)

    assert l.header == %{x: 0, y: 0, w: 160, h: 1}
    assert %{x: 0, y: 1, w: 26} = l.rail
    assert %{x: 26, w: 1} = l.rail_sep
    assert %{x: 134, w: 26} = l.crew
    assert %{x: 133, w: 1} = l.crew_sep
    # center spans between the separators
    assert l.center.x == 27
    assert l.center.x + l.center.w == l.crew_sep.x
    # composer sits under the center, same span, 3 rows, ending at the bottom
    assert l.composer.x == l.center.x and l.composer.w == l.center.w
    assert l.composer.y + l.composer.h == 40
    assert l.center.y + l.center.h == l.composer.y
  end

  test "medium: the crew rail collapses first" do
    l = Layout.compute(100, 30)
    assert l.rail
    assert l.crew == nil and l.crew_sep == nil
    assert l.center.x + l.center.w == 100
  end

  test "narrow: both rails collapse — the conversation takes the full width" do
    l = Layout.compute(70, 30)
    assert l.rail == nil and l.crew == nil
    assert l.center == %{x: 0, y: 1, w: 70, h: 26}
  end

  test "degenerate sizes never produce a non-positive center" do
    l = Layout.compute(5, 3)
    assert l.center.w >= 1 and l.center.h >= 1
  end
end
