defmodule Console.Panel.RailTest do
  @moduledoc """
  The always-on left rail: the open project's threads in the active workspace, the lobby in every
  project, ranked by what needs you — waiting, then working, then unread, then the rest. Two rows
  per thread: `▌! title`, then `○ lead · state`.
  """
  use ExUnit.Case, async: true

  import Console.PanelText, only: [lines: 1, row_text: 1, text: 1]

  alias Console.Panel.Rail

  @rect %{x: 0, y: 1, w: 30, h: 20}
  @now ~U[2026-09-25 12:00:00Z]

  defp thread(over) do
    Map.merge(
      %{
        id: 1,
        title: "a thread",
        project_id: 1,
        root: false,
        lead: "hronir",
        warm?: false,
        awaiting: nil,
        working: false,
        last_at: ~U[2026-09-25 09:00:00Z]
      },
      over
    )
  end

  defp data(over \\ %{}) do
    Map.merge(
      %{
        groups: [
          %{
            workspace: %{id: 1, name: "Machine"},
            projects: [%{id: 1, name: "Tlön"}, %{id: 2, name: "ficciones"}],
            threads: [
              thread(%{id: 9, title: "lobby", root: true, lead: "tertius", project_id: 2}),
              thread(%{id: 20, title: "quiet one"}),
              thread(%{id: 21, title: "busy one", working: true}),
              thread(%{id: 22, title: "asks you", prompt: %{id: 5, summary: "run mix ecto.reset?", options: []}}),
              thread(%{id: 23, title: "elsewhere", project_id: 2})
            ]
          },
          %{
            workspace: %{id: 2, name: "Accessibility"},
            projects: [%{id: 3, name: "excessibility"}],
            threads: [thread(%{id: 30, title: "hidden", project_id: 3})]
          }
        ],
        active_key: 1,
        open_project: 1,
        opened: nil,
        now: @now
      },
      over
    )
  end

  defp ids(data), do: Enum.map(Rail.entries(data), fn {:thread, t} -> t.id end)
  defp rows_of(rows, title), do: rows |> Enum.chunk_every(2) |> Enum.find(fn [first, _] -> row_text(first) =~ title end)

  describe "entries" do
    test "the open project's threads and the lobby, most urgent first — waiting, working, then the rest" do
      assert ids(data()) == [22, 21, 9, 20]
    end

    test "another project, and another workspace, are not listed" do
      refute 23 in ids(data())
      refute 30 in ids(data())
      assert ids(data(%{open_project: 2})) == [9, 23]
    end

    test "a project the workspace no longer has falls back to its first" do
      assert ids(data(%{open_project: 999})) == ids(data())
      assert Rail.open_project_id([%{id: 4}, %{id: 5}], nil) == 4
      assert Rail.open_project_id([], nil) == nil
    end

    test "attention ranks waiting (a prompt or a parked gate) over working over unread over quiet" do
      assert Rail.attention(%{prompt: %{}}) == 0
      assert Rail.attention(%{awaiting: "andrew", working: true}) == 0
      assert Rail.attention(%{working: true, unread?: true}) == 1
      assert Rail.attention(%{unread?: true}) == 2
      assert Rail.attention(%{}) == 3
    end
  end

  describe "render" do
    test "two rows per thread: the badge and title, then the lead and what it is doing" do
      rows = Rail.render(data(), @rect)
      assert length(rows) == 8

      assert [title, meta] = rows_of(rows, "asks you")
      assert row_text(title) =~ "! asks you"
      assert row_text(meta) =~ "hronir · waiting: run mix"

      assert [busy, busy_meta] = rows_of(rows, "busy one")
      assert row_text(busy) =~ "… busy one"
      assert row_text(busy_meta) =~ "hronir · working"
    end

    test "a quiet thread carries no badge and says how long ago it moved" do
      [title, meta] = rows_of(Rail.render(data(), @rect), "quiet one")
      refute row_text(title) =~ ~r/[!…•]/
      assert row_text(meta) =~ "hronir · 3h"
    end

    test "warmth is the dot on the second row — ● warm, ○ cold" do
      warm = data(%{groups: [%{workspace: %{id: 1, name: "M"}, projects: [], threads: [thread(%{warm?: true})]}]})
      assert [_, meta] = Rail.render(warm, @rect)
      assert row_text(meta) =~ "●"

      assert [_, cold] =
               Rail.render(
                 data(%{groups: [%{workspace: %{id: 1, name: "M"}, projects: [], threads: [thread(%{})]}]}),
                 @rect
               )

      assert row_text(cold) =~ "○"
    end

    test "only the OPEN thread renders inverse, both of its rows" do
      [title, meta] = rows_of(Rail.render(data(%{opened: 20}), @rect), "quiet one")
      assert Enum.all?(title ++ meta, fn {_t, style} -> style in [:selected, :selected_accent] end)

      [other, _] = rows_of(Rail.render(data(%{opened: 20}), @rect), "busy one")
      refute Enum.any?(other, fn {_t, style} -> style == :selected end)
    end

    test "the cursor is the ▌ gutter, and it still shows on the open thread" do
      rows = Rail.render(data(%{selected: 3, opened: 20}), @rect)
      [title, meta] = rows_of(rows, "quiet one")
      assert String.starts_with?(row_text(title), "▌")
      assert String.starts_with?(row_text(meta), "▌")
      refute rows |> lines() |> Enum.take(6) |> Enum.any?(&String.starts_with?(&1, "▌"))
    end

    test "rows clip to the rail's width, a long title included" do
      long =
        data(%{
          groups: [
            %{workspace: %{id: 1, name: "M"}, projects: [], threads: [thread(%{title: String.duplicate("x", 80)})]}
          ]
        })

      assert Enum.all?(Rail.render(long, %{@rect | w: 22}), &(String.length(row_text(&1)) == 22))
    end

    test "an empty project says so; an empty read says the server may be down" do
      empty = data(%{groups: [%{workspace: %{id: 1, name: "M"}, projects: [%{id: 1, name: "Tlön"}], threads: []}]})
      assert empty |> Rail.render(@rect) |> text() =~ "no open threads here"
      assert %{} |> Rail.render(@rect) |> text() =~ "is server up?"
    end
  end

  describe "pick and entry_at — two rows answer one thread" do
    test "either row of a thread opens it; past the last row picks nothing" do
      assert Rail.pick(data(), @rect, 0) == {:open_thread_view, 22}
      assert Rail.pick(data(), @rect, 1) == {:open_thread_view, 22}
      assert Rail.pick(data(), @rect, 2) == {:open_thread_view, 21}
      assert Rail.pick(data(), @rect, 99) == nil
      assert Rail.entry_at(%{}, @rect, 0) == nil
    end

    test "a scrolled rail resolves the row under the pointer, not the unscrolled list" do
      assert {:thread, %{id: 9}} = Rail.entry_at(data(%{scroll: 4}), @rect, 0)
      assert Rail.row_of(2) == 4
    end
  end

  test "age reads in the largest unit that fits" do
    assert Rail.age(~U[2026-09-25 11:59:30Z], @now) == "just now"
    assert Rail.age(~U[2026-09-25 11:15:00Z], @now) == "45m"
    assert Rail.age(~U[2026-09-22 12:00:00Z], @now) == "3d"
    assert Rail.age(~U[2026-08-01 12:00:00Z], @now) == "7w"
    assert Rail.age(nil, @now) == ""
  end

  test "hints name only keys that work" do
    assert Rail.hints(data()) == [{"j/k", "thread"}, {"⏎", "open"}, {"[ ]", "project"}, {"m", "move"}, {"d", "delete"}]
  end

  test "topics cover threads, sessions and workspaces" do
    assert Enum.sort(Rail.topics(%{})) ==
             Enum.sort([Server.Bus.threads_topic(), Server.Bus.sessions_topic(), Server.Bus.workspaces_topic()])
  end
end
