defmodule Console.Panel.WindowBarTest do
  @moduledoc """
  The top band framing the Tlön center: aleph's own window strip (moved out of the terminal, which
  now renders edge-to-edge) plus the engine/thread readout. A pure seam — same contract
  `terminal_test.exs` used to pin for the old in-terminal tab row.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.WindowBar

  @rect %{x: 0, y: 0, w: 100, h: 3}

  @tabs [
    %{name: "tertius", active?: true, index: "0", agent: "tertius-machine", warm?: true},
    %{name: "hronir", active?: false, index: "1", agent: "claude-machine", warm?: false},
    %{name: "general", active?: false, index: "2", agent: nil, warm?: false}
  ]

  test "renders each window as a tab: presence dot + window·agent, active highlighted" do
    [row] = WindowBar.render(%{tabs: @tabs, engine: :on, thread: 7}, @rect)
    text = Enum.map_join(row, fn {t, _} -> t end)

    assert text =~ "tertius·tertius-machine"
    assert text =~ "hronir·claude-machine"
    assert text =~ "general"
    assert text =~ "●"
    assert text =~ "○"

    assert Enum.any?(row, fn {t, s} -> t =~ "tertius·tertius-machine" and s == :selected end)
    assert Enum.any?(row, fn {t, s} -> t =~ "hronir·claude-machine" and s == :dim end)
  end

  test "the engine + focused thread render right-justified" do
    [row] = WindowBar.render(%{tabs: @tabs, engine: :on, thread: 7}, @rect)
    text = Enum.map_join(row, fn {t, _} -> t end)

    assert text =~ "claude"
    assert text =~ "#7"
  end

  test "engine off renders dim" do
    [row] = WindowBar.render(%{tabs: [], engine: :off, thread: nil}, @rect)
    assert Enum.any?(row, fn {t, s} -> t =~ "claude" and s == :dim end)
  end

  test "no leader tab active (a leaf's own t<id> window is the active tmux window) — none highlighted, C3.3" do
    tabs = [
      %{name: "tertius", active?: false, index: "0", agent: "tertius-machine", warm?: true},
      %{name: "hronir", active?: false, index: "1", agent: "claude-machine", warm?: false}
    ]

    [row] = WindowBar.render(%{tabs: tabs, engine: :on, thread: 7}, @rect)
    refute Enum.any?(row, fn {_t, s} -> s == :selected end)
  end

  describe "tab_at_x/2: which tab a click landed on" do
    test "a click inside a tab's label segment returns that tab" do
      assert WindowBar.tab_at_x(@tabs, 1).name == "tertius"
    end

    test "a click past the last tab is nil — no misfire on the filler" do
      assert WindowBar.tab_at_x(@tabs, 200) == nil
    end
  end
end
