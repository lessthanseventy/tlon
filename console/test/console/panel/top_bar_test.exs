defmodule Console.Panel.TopBarTest do
  @moduledoc """
  The frame's top line: `‹ workspace ›`, its project tabs with their loudest badge, and on the
  right the open thread's worktree and lead — the server-down alarm outranking all of it.
  """
  use ExUnit.Case, async: true

  import Console.PanelText, only: [row_text: 1]

  alias Console.Panel.TopBar

  @projects [%{id: 1, name: "Tlön", badge: {"!", :st_await}}, %{id: 2, name: "ficciones", badge: nil}]

  defp data(over \\ %{}),
    do: Map.merge(%{workspace: "Machine", workspace_id: 1, projects: @projects, open_project: 1, link: :up}, over)

  defp render(data, w \\ 80), do: TopBar.render(data, %{x: 0, y: 0, w: w, h: 1})

  test "the workspace between arrows, then its projects as tabs, each with its loudest badge" do
    [row] = render(data())
    assert row_text(row) =~ ~r/^ ‹ Machine › +Tlön ! +ficciones /
  end

  test "the open project's tab is inverse, badge included; the others are not" do
    [row] = render(data())
    assert {" Tlön", :selected} in row
    assert {" !", :selected_accent} in row
    assert {" ficciones", :normal} in row

    [row] = render(data(%{open_project: 2}))
    assert {" ficciones", :selected} in row
    assert {" !", :st_await} in row
  end

  test "another workspace waiting on you marks the chip with a !" do
    [row] = render(data(%{elsewhere?: true}))
    assert row_text(row) =~ " › !"
    [row] = render(data())
    refute row_text(row) =~ " › !"
  end

  test "the open thread's worktree, shortened, and its lead with a warmth dot sit on the right" do
    [row] = render(data(%{cwd: "/home/a/projects/tlon/.worktrees/t12", lead: "hronir", warm?: true}), 90)
    text = row_text(row)

    assert text =~ ~r/\.worktrees\/t12  ● hronir $/
    refute text =~ "/home/a"
    [cold] = render(data(%{lead: "hronir", warm?: false}))
    assert row_text(cold) =~ "○ hronir"
  end

  test "the row fills the width and the justified gap is neutral" do
    [row] = render(data(%{lead: "hronir", warm?: true}), 120)
    assert Console.Panel.row_width(row) == 120
    refute Enum.any?(row, fn {t, s} -> s != :normal and String.trim(t) == "" and String.length(t) >= 3 end)
  end

  test "a narrow frame keeps the server-down alarm and clips the tabs instead" do
    many = Enum.map(1..8, &%{id: &1, name: "project-#{&1}", badge: nil})
    [row] = render(data(%{projects: many, lead: "hronir", link: :down}), 40)
    text = row_text(row)

    assert text =~ "server down"
    refute text =~ "hronir"
    assert Console.Panel.row_width(row) <= 40
  end

  test "nothing crashes on an empty read" do
    [row] = render(%{link: :down}, 40)
    assert row_text(row) =~ "‹ — ›"
    assert row_text(row) =~ "server down"
  end

  describe "hit/2 — what a click at a column means, off the drawn segments" do
    test "the arrows step the workspace ring; the name is the workspace (its menu); a tab is its project" do
      assert TopBar.hit(data(), 1) == {:workspace_step, :prev}
      assert TopBar.hit(data(), 4) == :workspace
      assert TopBar.hit(data(), 11) == {:workspace_step, :next}

      [row] = render(data())
      text = row_text(row)
      {tlon, _} = :binary.match(text, "Tlön")
      {fic, _} = :binary.match(text, "ficciones")
      assert TopBar.hit(data(), String.length(binary_part(text, 0, tlon))) == {:project, 1}
      assert TopBar.hit(data(), String.length(binary_part(text, 0, fic))) == {:project, 2}
    end

    test "the gap, and past the tabs, is nothing" do
      assert TopBar.hit(data(), 14) == nil
      assert TopBar.hit(data(), 79) == nil
    end
  end
end
