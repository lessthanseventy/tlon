defmodule Console.Cockpit.DrawerTest do
  @moduledoc """
  The drawer (UX slice 1, task 4): today's rail panels and boards, over the CENTER — never over the
  rail or the two bars. Placements as plain data, like every other composition test.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit.Drawer
  alias Console.Panel
  alias Console.Tlon.Focus

  setup do
    Console.TestWorkspaces.put()
  end

  # A cockpit state, plus the frame's reads derived from it exactly as `do_render/1` does — the
  # drawer resolves its panes' data from THIS frame's reads.
  defp state(overrides) do
    state =
      Map.merge(
        %{
          drawer: nil,
          active_key: 0,
          board_cursor: {0, 0},
          focus: Focus.new(),
          sidebar: [],
          memory: nil,
          stack: nil,
          health: nil,
          detail: nil
        },
        overrides
      )

    reads =
      state
      |> Map.take([:active_key, :memory, :stack, :health, :detail])
      |> Map.merge(%{crew: nil, roster: [], triage: nil, activity: [], gates: [], scrolls: %{}})

    Map.put(state, :reads, reads)
  end

  test "closed: no placements" do
    assert Drawer.placements(state(%{drawer: nil}), 120, 40) == []
  end

  describe "open" do
    test "one Border with the pane tabs over the CENTER rect only — never the rail or the bars" do
      [{Panel.Border, border, rect} | content] = Drawer.placements(state(%{drawer: :memory}), 120, 40)

      # right of the rail (Console.View's rail_width/1 for w=120), between the two bars
      assert rect.x == max(22, div(120, 5)) + 1
      assert rect.w == 120 - rect.x
      assert rect.y == 1
      assert rect.y + rect.h == 39

      assert Enum.map(border.tabs, &elem(&1, 0)) == ~w(now crew memory stack roster triage tickets notes health config)
      assert Enum.any?(content, &match?({Panel.Memory, _, _}, &1))
    end

    test "the open pane's tab is the lit one" do
      [{Panel.Border, border, _rect} | _] = Drawer.placements(state(%{drawer: :stack}), 120, 40)

      assert Enum.filter(border.tabs, &elem(&1, 1)) == [{"stack", true}]
    end

    test "the content is inset inside the border" do
      [{Panel.Border, _, rect}, {_panel, _data, content}] = Drawer.placements(state(%{drawer: :now}), 120, 40)

      assert content.x > rect.x and content.y > rect.y
      assert content.x + content.w <= rect.x + rect.w
      assert content.y + content.h <= rect.y + rect.h
    end

    test "the focused pane gets the focus slice — its j/k cursor and section" do
      focus = %Focus{in_terminal?: false, column: :left, pane: 2, section: 1, cursors: %{Panel.Memory => 3}}
      memory = %{coverage: nil, pinned: [], habits: [%{}, %{}, %{}, %{}]}

      [_border, {Panel.Memory, data, _rect}] =
        Drawer.placements(state(%{drawer: :memory, focus: focus, memory: memory}), 120, 40)

      assert data.selected == 3
      assert data.section == 1
    end

    test "an open detail replaces the pane's content until Esc" do
      focus = %Focus{in_terminal?: false, detail?: true}
      detail = %{title: "FLOOR FACT", lines: [{"never ship on red", :normal}]}

      [_border, {panel, data, _rect}] =
        Drawer.placements(state(%{drawer: :memory, focus: focus, detail: detail}), 120, 40)

      assert panel == Panel.Detail
      assert data == detail
    end

    test "HEALTH renders the read the footer's old health segment showed" do
      health = %{version: "v1", funes_up: true, tlon_up: true, tools: []}

      [_border, {Panel.Health, data, _rect}] =
        Drawer.placements(state(%{drawer: :health, health: health}), 120, 40)

      # the open pane also carries the focus slice (selected/section); the health read rides intact
      assert Map.take(data, Map.keys(health)) == health
    end

    test "the boards are panes now — TICKETS carries the kanban cursor, NOTES its notes" do
      [_border, {Panel.TicketBoard, tickets, _}] = Drawer.placements(state(%{drawer: :tickets}), 120, 40)
      assert tickets.cursor == {0, 0}
      assert is_list(tickets.tickets)

      [_border, {Panel.NoteBoard, notes, _}] = Drawer.placements(state(%{drawer: :notes}), 120, 40)
      assert is_list(notes.notes)
    end
  end

  describe "the pane table" do
    test "the order is fixed and each atom maps to one panel" do
      assert Keyword.keys(Drawer.panes()) == ~w(now crew memory stack roster triage tickets notes health config)a
      assert Drawer.panel(:memory) == Panel.Memory
      # the Author lives here as CONFIG (UX slice 1, task 5)
      assert Drawer.panel(:config) == Panel.Author
      assert Drawer.panel(:tickets) == Panel.TicketBoard
      assert Drawer.panel(:now) == Panel.Activity
      assert Drawer.pane_modules() == Enum.map(Drawer.panes(), &elem(&1, 1))
    end

    test "keys walk the ring, clamped at both ends (h/l are not a carousel)" do
      assert Drawer.step(:now, -1) == :now
      assert Drawer.step(:now, +1) == :crew
      assert Drawer.step(:config, +1) == :config
      assert Drawer.at(3) == :stack
      assert Drawer.at(99) == nil
      assert Drawer.index(:stack) == 3
    end
  end

  test "covers?/3 is true inside the drawer's rect and false over the rail and the bars" do
    state = state(%{drawer: :memory, w: 120, h: 40})

    assert Drawer.covers?(state, 30, 10)
    refute Drawer.covers?(state, 3, 10), "the rail is never covered"
    refute Drawer.covers?(state, 30, 0), "the top bar is never covered"
    refute Drawer.covers?(state, 30, 39), "the footer is never covered"
    refute Drawer.covers?(%{state | drawer: nil}, 30, 10)
  end

  # The tab strip invites a click: a hit on a tab label on the drawer's top rule names its pane;
  # anywhere else on the drawer is nil (the pane underneath takes it). Mirrors Border.tab_at_x/2.
  test "tab_at/3 names the pane under a click on the tab strip, nil elsewhere" do
    state = state(%{drawer: :memory, w: 120, h: 40})
    [{Panel.Border, border, rect}] = Enum.take(Drawer.placements(state, 120, 40), 1)
    # the label runs: find where "stack" starts by asking the border itself
    x_of = fn label ->
      Enum.find(0..rect.w, fn x ->
        Panel.Border.tab_at_x(border, x) == Enum.find_index(border.tabs, &(elem(&1, 0) == label))
      end)
    end

    assert Drawer.tab_at(state, rect.x + x_of.("stack"), rect.y) == :stack
    assert Drawer.tab_at(state, rect.x + x_of.("health"), rect.y) == :health
    assert Drawer.tab_at(state, rect.x + 5, rect.y + 5) == nil, "inside the pane, not the strip"
    assert Drawer.tab_at(%{state | drawer: nil}, rect.x + 5, rect.y) == nil
  end
end
