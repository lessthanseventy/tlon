defmodule Console.Panel.LeavesTest do
  # LEAVES rollup (was ORBIS panel): the machine-scoped vantage — a compact lens over the leaf
  # threads (lead + status + conflicts), navigable in Tlön nav. On-screen paint is the eye test in a
  # real terminal; this pins the panel → styled-rows path headlessly.
  use ExUnit.Case, async: true

  alias Console.Panel.Leaves

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "nil data renders a placeholder, no crash (title lives on the frame now)" do
    text = nil |> Leaves.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "no machine threads"
  end

  test "renders the rollup summary counts and one line per leaf (lead + status)" do
    data = %{
      summary: %{open: 1, stalled: 1, done: 2, conflicts: 3},
      rows: [
        %{id: 2, title: "joke thread", lead: "pi-machine", status: :stalled, conflicts: 3},
        %{id: 3, title: "reaper fix", lead: "claude-machine", status: :open, conflicts: 0},
        %{id: 1, title: "shipped the seed", lead: "tertius-machine", status: :done, conflicts: 0}
      ]
    }

    text = data |> Leaves.render(@rect) |> lines() |> Enum.join("\n")

    # Rollup line: the operator's open / stalled / done buckets, with conflicts called out.
    assert text =~ "1 open"
    assert text =~ "1 stalled"
    assert text =~ "2 done"
    assert text =~ "3 conflicts"

    # Every leaf shows its title and its lead.
    assert text =~ "joke thread"
    assert text =~ "pi-machine"
    assert text =~ "reaper fix"
    assert text =~ "claude-machine"
    assert text =~ "shipped the seed"
    assert text =~ "tertius-machine"

    # A stalled leaf surfaces its conflict count so the trouble is visible at a glance.
    stalled_line = text |> String.split("\n") |> Enum.find(&(&1 =~ "joke thread"))
    assert stalled_line =~ "3"
  end

  test "no conflicts → the rollup line omits the conflicts clause (a clean board reads clean)" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 2, title: "a", lead: "pi-machine", status: :open, conflicts: 0},
        %{id: 3, title: "b", lead: "claude-machine", status: :open, conflicts: 0}
      ]
    }

    text = data |> Leaves.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "0 stalled"
    refute text =~ "conflict"
  end

  test "pick maps a leaf row to focusing that thread; the header rows and empties are no-ops" do
    data = %{
      summary: %{open: 1, stalled: 0, done: 0, conflicts: 0},
      rows: [%{id: 7, title: "a", lead: "pi-machine", status: :open, conflicts: 0}]
    }

    # Header block (summary / blank) then the first leaf row.
    assert Leaves.pick(data, @rect, 2) == {:focus_thread, 7}
    assert Leaves.pick(data, @rect, 0) == nil
    assert Leaves.pick(nil, @rect, 2) == nil
  end

  test "the selected leaf's title washes :selected; the rest stay :normal" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 2, title: "first", lead: "pi", status: :open, conflicts: 0},
        %{id: 3, title: "second", lead: "cc", status: :open, conflicts: 0}
      ],
      selected: 1
    }

    rows = Leaves.render(data, @rect)

    style_of = fn needle ->
      Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t == needle, do: s end) end)
    end

    assert style_of.("second") == :selected
    assert style_of.("first") == :normal
  end

  # C3.3: `attached` (the leaf whose own window IS the Workspace center) washes :selected too — distinct
  # from and independent of the j/k `selected` cursor.
  test "the attached leaf's title washes :selected even when the cursor (selected) is elsewhere" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 2, title: "first", lead: "pi", status: :open, conflicts: 0},
        %{id: 3, title: "second", lead: "cc", status: :open, conflicts: 0}
      ],
      selected: 0,
      attached: 3
    }

    rows = Leaves.render(data, @rect)

    style_of = fn needle ->
      Enum.find_value(rows, fn row -> Enum.find_value(row, fn {t, s} -> if t == needle, do: s end) end)
    end

    assert style_of.("first") == :selected
    assert style_of.("second") == :selected
  end

  # C3.2: the focused leader's leaves float to the top (stable) so the operator's active leader owns
  # the top of the panel; render and pick share the ordering so selection stays consistent.
  describe "focused leader's leaves float to the top" do
    defp grouping_data(focused_lead) do
      %{
        summary: %{open: 3, stalled: 0, done: 0, conflicts: 0},
        rows: [
          %{id: 1, title: "tX", lead: "tertius-machine", status: :open, conflicts: 0},
          %{id: 2, title: "hA", lead: "hronir-machine", status: :open, conflicts: 0},
          %{id: 3, title: "hB", lead: "hronir-machine", status: :open, conflicts: 0}
        ],
        focused_lead: focused_lead
      }
    end

    defp title_index(rows, needle), do: Enum.find_index(rows, fn row -> Enum.any?(row, fn {t, _} -> t == needle end) end)

    test "the two hronir leaves render before the tertius leaf when hronir is focused" do
      rows = Leaves.render(grouping_data("hronir-machine"), @rect)

      assert title_index(rows, "hA") < title_index(rows, "tX")
      assert title_index(rows, "hB") < title_index(rows, "tX")
    end

    test "no focused_lead → input order is preserved (stable)" do
      rows = Leaves.render(grouping_data(nil), @rect)
      assert title_index(rows, "tX") < title_index(rows, "hA")
    end

    test "pick honors the floated order — local_y of the first row is the focused leader's leaf" do
      data = grouping_data("hronir-machine")
      # first leaf row sits just below the header chrome (same offset the selected test uses)
      assert {:focus_thread, 2} = Leaves.pick(data, @rect, 2)
    end
  end

  test "hints/1 declares the pane's footer verbs" do
    assert Console.Panel.hints(Leaves, %{}) == [{"j/k", "leaves"}, {"⏎", "attach"}, {"y", "title"}, {"d", "delete"}]
  end

  test "yank/2 returns the cursor row's title, respecting the same float ordering as render/pick" do
    data = grouping_data("hronir-machine")
    assert Leaves.yank(data, 0) == {"title", "hA"}
    assert Leaves.yank(data, 9) == nil
    assert Leaves.yank(nil, 0) == nil
  end

  test "a TRACKED row carries its stage chip, gate, and blocking check (reshape slice C)" do
    data = %{
      summary: %{open: 2, stalled: 0, done: 0, conflicts: 0},
      rows: [
        %{id: 1, title: "plain chat", lead: "hronir-machine", status: :open, conflicts: 0},
        %{
          id: 2,
          title: "tracked work",
          lead: "hronir-machine",
          status: :open,
          conflicts: 0,
          stage: "build",
          awaiting: "andrew",
          blocking: %{cmd: "mix test", tail: "1 failure"}
        }
      ]
    }

    text = data |> Leaves.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "tracked work"
    assert text =~ "build"
    assert text =~ "⏸ awaiting andrew"
    assert text =~ "⚠ mix test — 1 failure"
    refute text =~ "plain chat · ⏸"
  end
end
