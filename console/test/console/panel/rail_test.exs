defmodule Console.Panel.RailTest do
  @moduledoc """
  The always-on left rail (UX slice 1, design 2026-09-08 §2): workspaces, and under the ACTIVE one
  its threads. A thread row is warmth dot · title · at most ONE badge, by priority
  waiting-on-you > unread > working.
  """
  use ExUnit.Case, async: true

  import Console.PanelText, only: [row_text: 1, text: 1]

  alias Console.Panel.Rail

  @rect %{x: 0, y: 1, w: 24, h: 20}

  defp thread(over) do
    Map.merge(%{id: 1, title: "a thread", warm?: false, awaiting: nil, unread?: false, working: false}, over)
  end

  defp data(over \\ %{}) do
    Map.merge(
      %{
        groups: [
          %{
            workspace: %{id: 1, name: "Tlön"},
            channels: [
              %{
                id: 10,
                name: "general",
                kind: "general",
                threads: [
                  thread(%{id: 9, title: "general", warm?: true, awaiting: "andrew", unread?: true}),
                  thread(%{id: 8, title: "aleph", unread?: true, working: true})
                ]
              },
              %{id: 11, name: "ideas", kind: "topic", threads: [thread(%{id: 7, title: "folded", working: true})]}
            ]
          },
          %{
            workspace: %{id: 2, name: "ficciones"},
            channels: [%{id: 12, name: "general", kind: "general", threads: [thread(%{id: 5, title: "hidden"})]}]
          }
        ],
        active_key: 1,
        open_channel: nil,
        opened: 9
      },
      over
    )
  end

  # one workspace, #general only, these threads
  defp solo(threads),
    do: %{
      groups: [
        %{workspace: %{id: 1, name: "Tlön"}, channels: [%{id: 10, name: "general", kind: "general", threads: threads}]}
      ]
    }

  defp rows(over \\ %{}), do: Rail.render(data(over), @rect)
  defp row_with(rows, substr), do: Enum.find(rows, fn row -> row_text(row) =~ substr end)

  test "a coworker waiting on a dialog is awaiting you — the ! badge, before unread and working" do
    rows =
      rows(
        solo([
          thread(%{title: "orient", prompt: %{id: 7, summary: "bash: env", options: []}, unread?: true, working: true})
        ])
      )

    row = row_text(row_with(rows, "orient"))

    assert row =~ "!"
    refute row =~ "•"
  end

  describe "render" do
    test "workspaces, then the ACTIVE one's threads; one badge per row by priority" do
      texts = Enum.map(rows(), &row_text/1)

      assert Enum.any?(texts, &(&1 =~ "Tlön"))
      assert Enum.any?(texts, &(&1 =~ "ficciones"))
      # waiting on you beats unread
      assert Enum.any?(texts, &(&1 =~ "general" and &1 =~ "!"))
      # unread beats working
      assert Enum.any?(texts, &(&1 =~ "aleph" and &1 =~ "•" and not (&1 =~ "!")))
    end

    test "only the active workspace's channels are listed, and only the OPEN channel's threads" do
      refute text(rows()) =~ "hidden"
      refute text(rows(%{active_key: 2})) =~ "aleph"
      assert text(rows(%{active_key: 2})) =~ "hidden"
      # #ideas is folded: its thread is hidden, its strongest badge shows on the channel row
      assert row_text(row_with(rows(), "#ideas")) =~ "…"
      refute text(rows()) =~ "folded"
      # open it: its thread unfolds, #general folds
      assert text(rows(%{open_channel: 11})) =~ "folded"
      refute text(rows(%{open_channel: 11})) =~ "aleph"
    end

    test "a working thread with nothing else pending gets the working badge alone" do
      rows = rows(solo([thread(%{title: "build", working: true})]))

      assert row_text(row_with(rows, "build")) =~ "…"
    end

    test "a quiet thread carries no badge at all" do
      rows = rows(solo([thread(%{title: "quiet"})]))
      row = row_text(row_with(rows, "quiet"))

      refute row =~ "!"
      refute row =~ "•"
      refute row =~ "…"
    end

    test "warmth is a dot per thread — ● warm, ○ cold (the pair Roster and the top bar use)" do
      assert row_text(row_with(rows(), " general")) =~ "●"
      assert row_text(row_with(rows(), "aleph")) =~ "○"
    end

    test "the OPEN thread's dot is still its warmth — an open COLD thread reads ○, like the top bar" do
      row = row_text(row_with(rows(%{opened: 8}), "aleph"))

      assert row =~ "○"
      refute row =~ "●"
    end

    test "the OPEN thread and the ACTIVE workspace render as the selected face" do
      rows = rows()
      styles = fn substr -> rows |> row_with(substr) |> Enum.map(fn {_t, s} -> s end) end

      assert :selected in styles.(" general")
      assert :selected in styles.("Tlön")
      refute :selected in styles.("aleph")
      refute :selected in styles.("ficciones")
    end

    test "the nav cursor marks its row without stealing the active face" do
      # cursor 2 = the first thread under #general (row 0 the workspace, row 1 the channel).
      rows = rows(%{selected: 2, opened: nil})

      assert :accent in (rows |> row_with(" general") |> Enum.map(fn {_t, s} -> s end))
    end

    test "an empty read renders a prompt, not a crash" do
      assert [row] = Rail.render(%{groups: [], active_key: nil}, @rect)
      assert row_text(row) =~ "no workspaces"
    end

    test "a long title at the floor width (22) still ends in its badge" do
      long = String.duplicate("x", 80)
      rect = %{@rect | w: 22}

      rows =
        Rail.render(
          data(%{
            groups: [
              %{
                workspace: %{id: 1, name: "T"},
                channels: [
                  %{id: 1, name: "general", kind: "general", threads: [thread(%{title: long, awaiting: "andrew"})]}
                ]
              }
            ]
          }),
          rect
        )

      row = rows |> Enum.map(&row_text/1) |> Enum.find(&(&1 =~ "xxx"))

      assert String.ends_with?(row, "!")
      assert Console.Panel.row_width(row_with(rows, "xxx")) <= 22
    end

    test "rows clip to the rail's width" do
      long = String.duplicate("x", 80)
      rows = rows(solo([thread(%{title: long})]))

      assert Enum.all?(rows, &(Console.Panel.row_width(&1) <= @rect.w))
    end
  end

  describe "pick" do
    test "a thread row opens that thread; a workspace row switches to it" do
      # row 0 = the active workspace, 1 = #general, 2..3 its threads, 4 = #ideas, 5 = the next workspace.
      assert Rail.pick(data(), @rect, 0) == {:switch_space, 1}
      assert Rail.pick(data(), @rect, 1) == {:open_channel, 10}
      assert Rail.pick(data(), @rect, 2) == {:open_thread_view, 9}
      assert Rail.pick(data(), @rect, 3) == {:open_thread_view, 8}
      assert Rail.pick(data(), @rect, 4) == {:open_channel, 11}
      assert Rail.pick(data(), @rect, 5) == {:switch_space, 2}
    end

    test "a click past the last row picks nothing" do
      assert Rail.pick(data(), @rect, 99) == nil
    end
  end

  describe "entry_at/3 — the right-click context menu's target" do
    test "every row answers its entry: workspace, channel or thread" do
      assert Rail.entry_at(data(), @rect, 0) == {:workspace, %{id: 1, name: "Tlön"}}
      assert {:channel, %{id: 10}} = Rail.entry_at(data(), @rect, 1)
      assert {:thread, %{id: 9}} = Rail.entry_at(data(), @rect, 2)
      assert Rail.entry_at(data(), @rect, 5) == {:workspace, %{id: 2, name: "ficciones"}}
      assert Rail.entry_at(data(), @rect, 99) == nil
      assert Rail.entry_at(%{}, @rect, 0) == nil
    end

    test "a scrolled rail resolves the row under the CURSOR, not the unscrolled list" do
      assert Rail.entry_at(data(%{scroll: 5}), @rect, 0) == {:workspace, %{id: 2, name: "ficciones"}}
    end
  end

  describe "projects — the open channel's threads under their project" do
    defp by_project do
      %{
        groups: [
          %{
            workspace: %{id: 1, name: "Tlön"},
            projects: [%{id: 1, name: "Tlön"}, %{id: 6, name: "Machine"}, %{id: 7, name: "DeuceSeven"}],
            channels: [
              %{
                id: 10,
                name: "general",
                kind: "general",
                threads: [
                  thread(%{id: 9, title: "general", project_id: 6}),
                  thread(%{id: 81, title: "stale menard", project_id: 1}),
                  thread(%{id: 15, title: "bluetooth", project_id: 6})
                ]
              }
            ]
          }
        ],
        active_key: 1
      }
    end

    test "a channel's threads group under their project, in the workspace's project order; empty projects are not listed" do
      assert [
               {:workspace, _},
               {:channel, _},
               {:project, %{name: "Tlön"}},
               {:thread, %{id: 81}},
               {:project, %{name: "Machine"}},
               {:thread, %{id: 9}},
               {:thread, %{id: 15}}
             ] = Rail.entries(by_project())
    end

    test "a project row is a heading: it renders its name and picks nothing" do
      out = by_project() |> Rail.render(@rect) |> text()
      assert out =~ "Machine"
      refute out =~ "DeuceSeven"
      assert Rail.pick(by_project(), @rect, 2) == nil
    end

    test "one project (or none known) adds no heading — the flat list stays flat" do
      refute Enum.any?(Rail.entries(data()), &match?({:project, _}, &1))
    end
  end

  test "hints name only keys that work" do
    assert Rail.hints(data()) == [{"j/k", "row"}, {"⏎", "open"}, {"m", "move"}, {"#", "channel"}, {"d", "delete"}]
  end

  test "topics cover threads, sessions and workspaces" do
    assert Enum.sort(Rail.topics(%{})) ==
             Enum.sort([Server.Bus.threads_topic(), Server.Bus.sessions_topic(), Server.Bus.workspaces_topic()])
  end
end
