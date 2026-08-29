defmodule Console.CockpitLeavesAttachTest do
  @moduledoc """
  Leaves-Enter attach (Workspaces Slice 0, Task 2): pressing Enter on a leaf whose lead maps to a live
  Workspace tmux window ATTACHES that window in the center — PREVIEW (re-point) then COMMIT (focus in),
  reusing Task 1's `preview_focused/1` + `commit_preview/1`. A leaf with no live window can't attach
  yet (arbitrary-leaf PTYs are Slice 1) — it flashes the deferral and re-points nothing, never the
  old `active_key: :sessions` jump.

  C3.3: a leaf now MAY have its own live `t<id>` window (`ensure_thread_sessions`) — `attach_leaf/2`
  prefers that over the lead's window and sets `focused_session: {:leaf, id}`; the lead-window
  fallback below (the original Slice-0 behavior) sets `focused_session: {:leader, lead}` instead.
  See the "C3.3" describe block.

  These exercise `attach_leaf/2`, the pure decision the `:tlon_enter` → `jump_to_leaf` path runs
  before its (termbox-painting, un-unit-testable) render. The tmux runner is injected
  (`:console, :tlon_cmd`) so argv is asserted without a live server, the same seam the preview test
  uses. `previewed_window` is tmux's STRING window index (`"1"`), not an int.
  """
  use ExUnit.Case, async: false

  alias Console.Cockpit
  alias Console.Panel
  alias Console.Space
  alias Console.Tlon.Focus

  # Workspace fixture: the hardcoded fallback Workspace is gone (reshape slice A); suites
  # that render or drive a Workspace push one through the Console.Workspaces cache-down seam.
  setup do
    Console.TestWorkspaces.put()
  end

  setup do
    test_pid = self()

    # Fake tmux runner: records argv; `list-windows` reports three Workspace windows
    # (tertius@0, hronir@1, general@2), everything else (select-window) is a no-op success.
    Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
      send(test_pid, {:tmux, args})

      if Enum.member?(args, "list-windows"),
        do: {"1\t0\ttertius\n0\t1\thronir\n0\t2\tgeneral\n", 0},
        else: {"", 0}
    end)

    on_exit(fn -> Application.delete_env(:console, :tlon_cmd) end)
    :ok
  end

  # A Tlön nav state focused on the Leaves pane (right column, index 2 — matches Space.fetch(0)),
  # the item cursor on row 0, keys NOT forwarding (in_terminal? false).
  defp leaves_state(rows) do
    %{
      active_key: 0,
      focus: %Focus{in_terminal?: false, column: :right, pane: 2, cursors: %{Panel.Leaves => 0}},
      leaves: %{summary: %{}, rows: rows},
      stack: nil,
      memory: nil,
      flash: nil,
      previewed_window: nil
    }
  end

  # The right-column layout the cockpit derives for Tlön (Leaves at index 2), with the Leaves count
  # so the focus cursor resolves the row under it. `right` is pulled from the real `Space.fetch(0)`
  # (the same source `tlon_layout/1` uses) so a future reorder of `space.right` can't silently desync
  # this test; `focus.pane: 2` in leaves_state/1 mirrors Leaves' position in that column.
  defp leaves_layout(rows) do
    %{
      left: [Panel.Sidebar, Panel.Stack, Panel.Memory],
      right: Space.fetch(0).right,
      sections: %{},
      counts: %{Panel.Leaves => length(rows)}
    }
  end

  describe "attach_leaf/2 — the Leaves-Enter decision" do
    test "a leaf mapped to a live Workspace window attaches it: preview (string index) + commit (focus)" do
      rows = [%{id: "t1", title: "x", lead: "hronir"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.previewed_window == "1"
      assert next.focus.in_terminal? == true
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "w0:1"]}
      # Retargeted off the deleted Sessions space — the space stays Tlön, no jump.
      assert next.active_key == 0
    end

    test "a leaf with no live window flashes the Slice-1 deferral, re-points nothing, no crash" do
      rows = [%{id: "t9", title: "x", lead: "ghost"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.flash =~ "no live session"
      assert next.previewed_window == nil
      assert next.focus.in_terminal? == false
      refute_received {:tmux, ["-L", _sock, "select-window" | _]}
    end

    test "no leaf under the cursor (empty rollup) also flashes, never crashes" do
      next = Cockpit.attach_leaf(leaves_state([]), leaves_layout([]))
      assert next.flash =~ "no live session"
      assert next.previewed_window == nil
    end

    test "attach follows the rendered row order under a focused lead (same ordering yank uses)" do
      # Raw order: ghost's leaf first, hronir's second; hronir focused floats its leaf to row 0 on
      # screen (C3.2), so Enter at cursor 0 must attach hronir's window — not flash on ghost's.
      rows = [%{id: "t9", title: "x", lead: "ghost"}, %{id: "t1", title: "y", lead: "hronir"}]
      state = Map.put(leaves_state(rows), :focused_lead, "hronir")
      next = Cockpit.attach_leaf(state, leaves_layout(rows))

      assert next.previewed_window == "1"
      assert next.focus.in_terminal? == true
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "w0:1"]}
    end
  end

  describe "attach_leaf/2 — C3.3: prefer the leaf's own t<id> window" do
    setup do
      test_pid = self()

      # window 0 is the lead's own window, window 1 is the leaf's own `t<id>` window — a leaf with
      # BOTH live must prefer its own (id 42 here), never fall back to the lead's.
      Application.put_env(:console, :tlon_cmd, fn "tmux", args, _opts ->
        send(test_pid, {:tmux, args})

        if Enum.member?(args, "list-windows"),
          do: {"1\t0\thronir-machine\n0\t1\tt42\n", 0},
          else: {"", 0}
      end)

      on_exit(fn -> Application.delete_env(:console, :tlon_cmd) end)
      :ok
    end

    test "a leaf with a live t<id> window attaches ITS OWN window, not its lead's" do
      rows = [%{id: 42, title: "x", lead: "hronir-machine"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.focused_session == {:leaf, 42}
      assert next.previewed_window == "1"
      assert next.focus.in_terminal? == true
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "w0:1"]}
    end

    test "a leaf whose t<id> is absent falls back to its lead's window — focused_session stays a leader" do
      rows = [%{id: 99, title: "x", lead: "hronir-machine"}]
      next = Cockpit.attach_leaf(leaves_state(rows), leaves_layout(rows))

      assert next.focused_session == {:leader, "hronir-machine"}
      assert next.previewed_window == "0"
      assert next.focus.in_terminal? == true
      assert_received {:tmux, ["-L", _sock, "select-window", "-t", "w0:0"]}
    end
  end
end
