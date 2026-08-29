defmodule Console.Panel.OverviewTest do
  # CHORUS — Orbis' center, re-pointed from a per-thread feed to the per-WORKSPACE survey. On-screen
  # paint is the eye test; this pins the panel → styled-rows path headlessly (no termbox),
  # asserting the header + workspace row + its rollup summary, and (D0.3) the cursor-row wash.
  use ExUnit.Case, async: true

  alias Console.Panel.Overview

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "renders the ORBIS · workspaces header and one workspace row with its rollup summary" do
    data = %{
      workspaces: [
        %{
          id: 1,
          name: "Tlön",
          summary: %{open: 2, stalled: 1, done: 3, conflicts: 4},
          leaves: [%{id: 1}, %{id: 2}]
        }
      ]
    }

    text = data |> Overview.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "ORBIS · workspaces"
    assert text =~ "Tlön"

    # The workspace's summary line carries the leads/open/stalled/done/trouble rollup.
    assert text =~ "2 open"
    assert text =~ "1 stalled"
    assert text =~ "3 done"
    assert text =~ "4 conflicts"
  end

  test "no workspaces (funes down / empty) renders the header and a placeholder, no crash" do
    text = %{workspaces: []} |> Overview.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "ORBIS · workspaces"
    assert text =~ "no workspaces"
  end

  test "clicking a workspace row zooms to ITS OWN workspace id; the header is inert" do
    data = %{
      workspaces: [%{id: 9, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}]
    }

    # Header (0) + blank (1), then the workspace's rows start at y = 2.
    assert Overview.pick(data, @rect, 2) == {:switch_space, 9}
    assert Overview.pick(data, @rect, 0) == nil
  end

  test "with 2 workspaces, clicking the SECOND row's block zooms into its own id, not the first's" do
    data = %{
      workspaces: [
        %{id: 1, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []},
        %{id: 2, name: "Freedonia", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
      ]
    }

    # Each workspace block is 3 rows (head/summary/blank); workspace 1 spans content rows 2-4, workspace 2 5-7.
    assert Overview.pick(data, @rect, 2) == {:switch_space, 1}
    assert Overview.pick(data, @rect, 5) == {:switch_space, 2}
    assert Overview.pick(data, @rect, 8) == nil
  end

  test "the survey_cursor row washes :selected only while orbis_focus is :survey" do
    workspaces = [
      %{id: 1, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []},
      %{id: 2, name: "Freedonia", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
    ]

    rows = Overview.render(%{workspaces: workspaces, survey_cursor: 1, orbis_focus: :survey}, @rect)
    freedonia_head = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Freedonia" end))
    assert Enum.any?(freedonia_head, fn {_t, s} -> s == :selected end)
    tlon_head = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Tlön" end))
    refute Enum.any?(tlon_head, fn {_t, s} -> s == :selected end)

    # Same cursor, but the thread list has focus — no row washes :selected.
    rows2 = Overview.render(%{workspaces: workspaces, survey_cursor: 1, orbis_focus: :threads}, @rect)
    freedonia_head2 = Enum.find(rows2, &Enum.any?(&1, fn {t, _} -> t == "Freedonia" end))
    refute Enum.any?(freedonia_head2, fn {_t, s} -> s == :selected end)
  end
end
