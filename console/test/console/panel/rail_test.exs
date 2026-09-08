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
            threads: [
              thread(%{id: 9, title: "general", warm?: true, awaiting: "andrew", unread?: true}),
              thread(%{id: 8, title: "aleph", unread?: true, working: true})
            ]
          },
          %{workspace: %{id: 2, name: "ficciones"}, threads: [thread(%{id: 5, title: "hidden"})]}
        ],
        active_key: 1,
        opened: 9
      },
      over
    )
  end

  defp rows(over \\ %{}), do: Rail.render(data(over), @rect)
  defp row_with(rows, substr), do: Enum.find(rows, fn row -> row_text(row) =~ substr end)

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

    test "only the active workspace's threads are listed" do
      refute text(rows()) =~ "hidden"
      refute text(rows(%{active_key: 2})) =~ "general"
      assert text(rows(%{active_key: 2})) =~ "hidden"
    end

    test "a working thread with nothing else pending gets the working badge alone" do
      rows = rows(%{groups: [%{workspace: %{id: 1, name: "Tlön"}, threads: [thread(%{title: "build", working: true})]}]})

      assert row_text(row_with(rows, "build")) =~ "…"
    end

    test "a quiet thread carries no badge at all" do
      rows = rows(%{groups: [%{workspace: %{id: 1, name: "Tlön"}, threads: [thread(%{title: "quiet"})]}]})
      row = row_text(row_with(rows, "quiet"))

      refute row =~ "!"
      refute row =~ "•"
      refute row =~ "…"
    end

    test "warmth is a dot per thread — ● warm, ○ cold (the pair Roster and the top bar use)" do
      assert row_text(row_with(rows(), "general")) =~ "●"
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

      assert :selected in styles.("general")
      assert :selected in styles.("Tlön")
      refute :selected in styles.("aleph")
      refute :selected in styles.("ficciones")
    end

    test "the nav cursor marks its row without stealing the active face" do
      # cursor 1 = the first thread under the active workspace (row 0 is the workspace itself).
      rows = rows(%{selected: 1, opened: nil})

      assert :accent in (rows |> row_with("general") |> Enum.map(fn {_t, s} -> s end))
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
          data(%{groups: [%{workspace: %{id: 1, name: "T"}, threads: [thread(%{title: long, awaiting: "andrew"})]}]}),
          rect
        )

      row = rows |> Enum.map(&row_text/1) |> Enum.find(&(&1 =~ "xxx"))

      assert String.ends_with?(row, "!")
      assert Console.Panel.row_width(row_with(rows, "xxx")) <= 22
    end

    test "rows clip to the rail's width" do
      long = String.duplicate("x", 80)
      rows = rows(%{groups: [%{workspace: %{id: 1, name: "Tlön"}, threads: [thread(%{title: long})]}]})

      assert Enum.all?(rows, &(Console.Panel.row_width(&1) <= @rect.w))
    end
  end

  describe "pick" do
    test "a thread row opens that thread; a workspace row switches to it" do
      # row 0 = the active workspace, rows 1..2 its threads, row 3 the next workspace.
      assert Rail.pick(data(), @rect, 0) == {:switch_space, 1}
      assert Rail.pick(data(), @rect, 1) == {:open_thread_view, 9}
      assert Rail.pick(data(), @rect, 2) == {:open_thread_view, 8}
      assert Rail.pick(data(), @rect, 3) == {:switch_space, 2}
    end

    test "a click past the last row picks nothing" do
      assert Rail.pick(data(), @rect, 99) == nil
    end
  end

  describe "workspace_at/3 — the right-click context menu's target" do
    test "a workspace row answers its workspace; a thread row answers nothing" do
      assert Rail.workspace_at(data(), @rect, 0) == %{id: 1, name: "Tlön"}
      assert Rail.workspace_at(data(), @rect, 1) == nil
      assert Rail.workspace_at(data(), @rect, 3) == %{id: 2, name: "ficciones"}
      assert Rail.workspace_at(data(), @rect, 99) == nil
      assert Rail.workspace_at(%{}, @rect, 0) == nil
    end

    test "a scrolled rail resolves the row under the CURSOR, not the unscrolled list" do
      assert Rail.workspace_at(data(%{scroll: 3}), @rect, 0) == %{id: 2, name: "ficciones"}
    end
  end

  test "hints name only keys that work" do
    assert Rail.hints(data()) == [{"j/k", "row"}, {"⏎", "open"}, {"[ ]", "space"}]
  end

  test "topics cover threads, sessions and workspaces" do
    assert Enum.sort(Rail.topics(%{})) ==
             Enum.sort([Server.Bus.threads_topic(), Server.Bus.sessions_topic(), Server.Bus.workspaces_topic()])
  end
end
