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
      prev = %{active_key: 2, scrolls: %{a: 3}}
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
  describe "context_entry/2 — the right-click menu's target" do
    @rail_data %{
      groups: [
        %{
          workspace: %{id: 0, name: "Tlön"},
          channels: [%{id: 1, name: "general", kind: "general", threads: [%{id: 9, title: "general"}]}]
        },
        %{workspace: %{id: 1, name: "ficciones"}, channels: []}
      ],
      active_key: 0
    }
    @rect %{x: 0, y: 1, w: 24, h: 20}

    test "a rail row answers its entry — workspace, channel or thread" do
      assert Cockpit.context_entry({Rail, @rail_data, @rect}, 1) == {:workspace, %{id: 0, name: "Tlön"}}
      assert {:channel, %{id: 1}} = Cockpit.context_entry({Rail, @rail_data, @rect}, 2)
      assert {:thread, %{id: 9}} = Cockpit.context_entry({Rail, @rail_data, @rect}, 3)
      assert Cockpit.context_entry({Rail, @rail_data, @rect}, 4) == {:workspace, %{id: 1, name: "ficciones"}}
    end

    test "another panel, or a miss, answers nothing" do
      assert Cockpit.context_entry({Rail, @rail_data, @rect}, 9) == nil
      assert Cockpit.context_entry({Console.Panel.ThreadStack, %{}, @rect}, 1) == nil
      assert Cockpit.context_entry(nil, 1) == nil
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

  describe "delete_flash/1 — the thread and what became of its worktree" do
    test "says gone, kept (with the reason), or nothing about a worktree it never had" do
      t = %{title: "busy"}
      assert Cockpit.delete_flash({:ok, t, :none}) == "deleted “busy”"
      assert Cockpit.delete_flash({:ok, t, {:removed, "/x/.worktrees/t1"}}) == "deleted “busy” and its worktree"
      assert Cockpit.delete_flash({:ok, t, {:kept, "work/t1 has unmerged commits"}}) =~ "worktree kept: work/t1"
      assert Cockpit.delete_flash({:error, :root_machine_thread}) =~ "root"
    end
  end
end
