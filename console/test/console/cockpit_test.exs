defmodule Console.CockpitTest do
  @moduledoc """
  The cockpit is a TTY-grabbing GenServer, so only its PURE seams are unit-tested here.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit
  alias Console.Panel.Rail

  doctest Console.Cockpit

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  describe "reset_scrolls/2" do
    test "a space switch drops every panel's scroll offset; otherwise they persist" do
      prev = %{active_key: 2, scrolls: %{a: 3}}
      assert Cockpit.reset_scrolls(prev, %{prev | active_key: 1}).scrolls == %{}
      assert Cockpit.reset_scrolls(prev, %{prev | scrolls: %{a: 4}}).scrolls == %{a: 4}
    end
  end

  describe "context_entry/3 — the right-click menu's target" do
    @rail_data %{
      groups: [
        %{
          workspace: %{id: 0, name: "Machine"},
          projects: [%{id: 1, name: "Tlön"}],
          threads: [%{id: 9, title: "lobby", root: true, project_id: 1}, %{id: 12, title: "rail", project_id: 1}]
        }
      ],
      active_key: 0
    }
    @rect %{x: 0, y: 1, w: 24, h: 20}

    test "either row of a rail thread answers that thread" do
      assert {:thread, %{id: 9}} = Cockpit.context_entry({Rail, @rail_data, @rect}, 3, 1)
      assert {:thread, %{id: 9}} = Cockpit.context_entry({Rail, @rail_data, @rect}, 3, 2)
      assert {:thread, %{id: 12}} = Cockpit.context_entry({Rail, @rail_data, @rect}, 3, 3)
    end

    test "the top bar's workspace name answers the workspace — its menu's door; a tab does not" do
      bar = %{
        workspace: "Machine",
        workspace_id: 0,
        projects: [%{id: 1, name: "Tlön", badge: nil}],
        open_project: 1,
        link: :up
      }

      rect = %{x: 0, y: 0, w: 80, h: 1}

      assert Cockpit.context_entry({Console.Panel.TopBar, bar, rect}, 5, 0) == {:workspace, %{id: 0, name: "Machine"}}
      assert Cockpit.context_entry({Console.Panel.TopBar, bar, rect}, 16, 0) == nil
    end

    test "another panel, or a miss, answers nothing" do
      assert Cockpit.context_entry({Rail, @rail_data, @rect}, 3, 9) == nil
      assert Cockpit.context_entry({Console.Panel.ThreadStack, %{}, @rect}, 3, 1) == nil
      assert Cockpit.context_entry(nil, 3, 1) == nil
    end
  end

  # The center [chat]|[terminal] toggle (reshape slice D) — the pure flip behind the `v` verb.
  describe "toggle_center_view/1" do
    test "flips terminal ↔ chat" do
      assert Cockpit.toggle_center_view(%{center_view: :terminal}).center_view == :chat
      assert Cockpit.toggle_center_view(%{center_view: :chat}).center_view == :terminal
    end
  end

  # A typed character changes `input` (and clears a flash) and nothing else — that repaint reuses
  # the last frame's reads instead of re-reading the world over erpc (2026-09-08, Andrew: typing
  # "felt a tiny bit laggy"). Anything else that moved means a real frame.
  describe "typing_only?/2 — the cheap-repaint predicate" do
    test "input changed, nothing else: typing" do
      before = %{input: %{kind: :reply, buffer: "a"}, flash: "spawned", focus: :x, reads: %{}}
      after_ = %{before | input: %{kind: :reply, buffer: "ab"}, flash: nil}
      assert Cockpit.typing_only?(before, after_)
    end

    test "a cursor/focus/scroll change is a real frame" do
      before = %{input: %{kind: :reply, buffer: "a"}, flash: nil, focus: :x, reads: %{}}
      refute Cockpit.typing_only?(before, %{before | input: %{kind: :reply, buffer: "ab"}, focus: :y})
    end

    test "no reads cached yet, or no input open: never cheap" do
      before = %{input: %{kind: :reply, buffer: "a"}, flash: nil, focus: :x, reads: nil}
      refute Cockpit.typing_only?(before, %{before | input: %{kind: :reply, buffer: "ab"}})
      closed = %{input: nil, flash: nil, focus: :x, reads: %{}}
      refute Cockpit.typing_only?(closed, closed)
    end
  end
end
