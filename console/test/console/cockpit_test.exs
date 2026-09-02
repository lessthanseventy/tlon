defmodule Console.CockpitTest do
  @moduledoc """
  The cockpit is a TTY-grabbing GenServer, so only its PURE seams are unit-tested here.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit

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

  # The center [chat]|[terminal] toggle (reshape slice D) — the pure flip behind the `v` verb.
  describe "toggle_center_view/1" do
    test "flips terminal ↔ chat" do
      assert Cockpit.toggle_center_view(%{center_view: :terminal}).center_view == :chat
      assert Cockpit.toggle_center_view(%{center_view: :chat}).center_view == :terminal
    end
  end
end
