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

  # The center [chat]|[terminal] toggle (reshape slice D) — the pure flip behind the `v` verb.
  describe "toggle_center_view/1" do
    test "flips terminal ↔ chat" do
      assert Cockpit.toggle_center_view(%{center_view: :terminal}).center_view == :chat
      assert Cockpit.toggle_center_view(%{center_view: :chat}).center_view == :terminal
    end
  end
end
