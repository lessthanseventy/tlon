defmodule Console.Panel.OverviewTest do
  # HOME — the god-view dashboard (Slice D2): a stat header + one boxed card per workspace with its
  # open/stalled/done tally + top threads. Pins the panel → styled-rows path headlessly (no termbox).
  use ExUnit.Case, async: true

  alias Console.Panel.Overview

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows), do: Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _s} -> t end) end)

  test "renders the HOME header + a boxed workspace card with its dot tally and top threads" do
    data = %{
      workspaces: [
        %{
          id: 1,
          name: "Tlön",
          summary: %{open: 2, stalled: 1, done: 3, conflicts: 4},
          leaves: [%{id: 1, title: "redis cache", lead: "hronir", status: :open}]
        }
      ]
    }

    text = data |> Overview.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "HOME"
    assert text =~ "Tlön"
    # the tally (dots rendered separately; the counts read in the header line)
    assert text =~ "2 open"
    assert text =~ "1 stalled"
    assert text =~ "3 done"
    # the per-thread rows are now surfaced (were discarded before)
    assert text =~ "redis cache"
    assert text =~ "hronir"
    # a boxed card is drawn
    assert text =~ "╭─"
  end

  test "caps threads per card and notes the remainder" do
    leaves = for i <- 1..7, do: %{id: i, title: "t#{i}", lead: "x", status: :open}
    data = %{workspaces: [%{id: 1, name: "W", summary: %{open: 7, stalled: 0, done: 0, conflicts: 0}, leaves: leaves}]}
    text = data |> Overview.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "t1"
    assert text =~ "+3 more"
  end

  test "no workspaces renders the header and a placeholder, no crash" do
    text = %{workspaces: []} |> Overview.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "HOME"
    assert text =~ "no workspaces"
  end

  test "clicking a workspace card zooms to ITS OWN id; the header is inert" do
    data = %{workspaces: [%{id: 9, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}]}
    # header is 3 rows; the first card's top border is at local_y 3.
    assert Overview.pick(data, @rect, 3) == {:switch_space, 9}
    assert Overview.pick(data, @rect, 0) == nil
  end

  test "with 2 workspaces, clicking the SECOND card zooms into its own id, not the first's" do
    data = %{
      workspaces: [
        %{id: 1, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []},
        %{id: 2, name: "Freedonia", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
      ]
    }

    # Empty-leaf card = 3 rows + 1 blank = 4 tall. Card 1 covers content 0-3 (local_y 3-6), card 2 4-7 (7-10).
    assert Overview.pick(data, @rect, 3) == {:switch_space, 1}
    assert Overview.pick(data, @rect, 7) == {:switch_space, 2}
    assert Overview.pick(data, @rect, 20) == nil
  end

  test "the survey_cursor card's title washes :selected only while orbis_focus is :survey" do
    workspaces = [
      %{id: 1, name: "Tlön", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []},
      %{id: 2, name: "Freedonia", summary: %{open: 0, stalled: 0, done: 0, conflicts: 0}, leaves: []}
    ]

    rows = Overview.render(%{workspaces: workspaces, survey_cursor: 1, orbis_focus: :survey}, @rect)
    freedonia = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Freedonia" end))
    assert Enum.any?(freedonia, fn {_t, s} -> s == :selected end)
    tlon = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Tlön" end))
    refute Enum.any?(tlon, fn {_t, s} -> s == :selected end)
  end
end
