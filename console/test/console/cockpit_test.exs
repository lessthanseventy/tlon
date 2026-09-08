defmodule Console.CockpitTest do
  @moduledoc """
  The cockpit is a TTY-grabbing GenServer, so only its PURE seams are unit-tested here.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit
  alias Console.Panel.Rail

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  describe "reset_scrolls/2" do
    test "a space switch drops every panel's scroll offset; otherwise they persist" do
      prev = %{active_key: :orbis, scrolls: %{a: 3}}
      assert Cockpit.reset_scrolls(prev, %{prev | active_key: 1}).scrolls == %{}
      assert Cockpit.reset_scrolls(prev, %{prev | scrolls: %{a: 4}}).scrolls == %{a: 4}
    end
  end

  describe "thread_title/1 — a title from the opening message" do
    test "first line, trimmed, capped at 60 chars" do
      assert Cockpit.thread_title("  fix the gate  \nmore detail") == "fix the gate"
      assert Cockpit.thread_title(String.duplicate("x", 80)) == String.duplicate("x", 60)
    end
  end

  # UX slice 1, task 2: the workspace context menu's door moved with the spine — the RAIL carries
  # the workspace rows now, so a right click resolves through it.
  describe "context_workspace/2 — the right-click menu's target" do
    @rail_data %{
      groups: [
        %{workspace: %{id: 0, name: "Tlön"}, threads: [%{id: 9, title: "general"}]},
        %{workspace: %{id: 1, name: "ficciones"}, threads: []}
      ],
      active_key: 0
    }
    @rect %{x: 0, y: 1, w: 24, h: 20}

    test "a workspace row in the rail answers its workspace" do
      assert Cockpit.context_workspace({Rail, @rail_data, @rect}, 1) == %{id: 0, name: "Tlön"}
      assert Cockpit.context_workspace({Rail, @rail_data, @rect}, 3) == %{id: 1, name: "ficciones"}
    end

    test "a thread row, another panel, or a miss answers nothing" do
      assert Cockpit.context_workspace({Rail, @rail_data, @rect}, 2) == nil
      assert Cockpit.context_workspace({Console.Panel.ThreadStack, %{}, @rect}, 1) == nil
      assert Cockpit.context_workspace(nil, 1) == nil
    end
  end

  # The center [chat]|[terminal] toggle (reshape slice D) — the pure flip behind the `v` verb.
  describe "toggle_center_view/1" do
    test "flips terminal ↔ chat" do
      assert Cockpit.toggle_center_view(%{center_view: :terminal}).center_view == :chat
      assert Cockpit.toggle_center_view(%{center_view: :chat}).center_view == :terminal
    end
  end
end
