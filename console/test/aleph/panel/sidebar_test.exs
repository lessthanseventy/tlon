defmodule Console.Panel.SidebarTest do
  @moduledoc """
  The Slack-shaped left sidebar (reshape slice D): Home, then one group per workspace —
  its unified thread list (working/stage/awaiting chips) and its crew with presence —
  rendered over `Server.Board.sidebar/0`'s read. Replaces the SPACES picker: workspace
  headers ARE the space nav (click/Enter switches), threads focus on click.
  """
  use ExUnit.Case, async: true

  alias Console.Panel.Sidebar

  defp text(row), do: Enum.map_join(row, fn {t, _style} -> t end)
  defp texts(rows), do: Enum.map(rows, &text/1)

  @rect %{x: 0, y: 0, w: 40, h: 30}

  defp thread(over) do
    Map.merge(
      %{
        id: 1,
        workspace_id: 1,
        title: "a thread",
        root: false,
        stage: nil,
        awaiting: nil,
        lead: nil,
        working: false,
        last_at: nil
      },
      over
    )
  end

  defp groups do
    [
      %{
        workspace: %{id: 1, name: "ficciones"},
        threads: [
          thread(%{id: 10, title: "general", root: true}),
          thread(%{id: 11, title: "fix the tick crash", working: true, stage: "build", lead: "hronir"}),
          thread(%{id: 12, title: "review pass", stage: "verify", awaiting: "operator"})
        ],
        crew: [
          %{name: "hronir", archetype: "builder", working: true},
          %{name: "tertius", archetype: "surveyor", working: false}
        ]
      },
      %{
        workspace: %{id: 2, name: "sandbox"},
        threads: [],
        crew: []
      }
    ]
  end

  test "renders Home, workspace headers, threads with chips, and crew with presence" do
    rows = Sidebar.render(%{groups: groups(), active_key: :orbis}, @rect)
    lines = texts(rows)

    # Home leads (the collapsed god-view) and is marked active.
    assert Enum.at(lines, 0) =~ "Home"
    assert Enum.at(lines, 0) =~ "▸"

    # Both workspace headers present, in read order.
    fic = Enum.find_index(lines, &(&1 =~ "ficciones"))
    sand = Enum.find_index(lines, &(&1 =~ "sandbox"))
    assert fic < sand

    # The root thread renders as the workspace's channel.
    assert Enum.any?(lines, &(&1 =~ "# general"))
    # A working thread carries the ⋯ chip; a tracked one its stage chip.
    assert Enum.any?(lines, &(&1 =~ "⋯" and &1 =~ "fix the tick crash" and &1 =~ "build"))
    # An awaiting gate is called out.
    assert Enum.any?(lines, &(&1 =~ "review pass" and &1 =~ "⏸"))
    # Crew presence: working ●, idle ○.
    assert Enum.any?(lines, &(&1 =~ "● hronir"))
    assert Enum.any?(lines, &(&1 =~ "○ tertius"))
  end

  test "the active workspace header carries the ▸ highlight instead of Home" do
    rows = Sidebar.render(%{groups: groups(), active_key: 2}, @rect)
    lines = texts(rows)

    refute Enum.at(lines, 0) =~ "▸"
    assert Enum.any?(lines, &(&1 =~ "▸" and &1 =~ "sandbox"))
  end

  test "the nav cursor marks the pickable row Enter would switch to" do
    # cursor 0 = Home, 1 = first workspace, 2 = second.
    rows = Sidebar.render(%{groups: groups(), active_key: :orbis, selected: 2}, @rect)
    lines = texts(rows)

    assert Enum.any?(lines, &(&1 =~ "→" and &1 =~ "sandbox"))
  end

  test "key_at resolves the cursor to a space key: Home then workspace ids" do
    data = %{groups: groups(), active_key: :orbis}
    assert Sidebar.key_at(data, 0) == :orbis
    assert Sidebar.key_at(data, 1) == 1
    assert Sidebar.key_at(data, 2) == 2
    assert Sidebar.key_at(data, 3) == nil
  end

  test "pick: a workspace header switches, a thread row focuses, crew is inert" do
    data = %{groups: groups(), active_key: :orbis}
    lines = texts(Sidebar.render(data, %{@rect | h: 10_000}))

    home_y = Enum.find_index(lines, &(&1 =~ "Home"))
    fic_y = Enum.find_index(lines, &(&1 =~ "ficciones"))
    thread_y = Enum.find_index(lines, &(&1 =~ "fix the tick crash"))
    crew_y = Enum.find_index(lines, &(&1 =~ "● hronir"))

    assert Sidebar.pick(data, @rect, home_y) == {:switch_space, :orbis}
    assert Sidebar.pick(data, @rect, fic_y) == {:switch_space, 1}
    assert Sidebar.pick(data, @rect, thread_y) == {:focus_thread, 11}
    assert Sidebar.pick(data, @rect, crew_y) == nil
  end

  test "no workspaces (funes down) still renders Home and a quiet note" do
    rows = Sidebar.render(%{groups: [], active_key: :orbis}, @rect)
    lines = texts(rows)

    assert Enum.at(lines, 0) =~ "Home"
    assert Enum.any?(lines, &(&1 =~ "no workspaces"))
  end
end
