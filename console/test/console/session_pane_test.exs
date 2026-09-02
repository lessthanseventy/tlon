defmodule Console.SessionPaneTest do
  # The launch spec for the toggleable right session pane (2026-08-31): a grouped tmux client pinned
  # to the selected thread's lead window. Only the command SHAPE is asserted here — the live attach
  # semantics (grouping, resize) are Andrew's kitty pass.
  use ExUnit.Case, async: true

  alias Console.SessionPane

  test "command builds a grouped, window-pinned tmux attach for the lead window" do
    assert {"/bin/bash", ["-lc", script]} = SessionPane.command(1, 3)

    # a grouped session (-t w1) so the pane keeps its own current window, then selects the lead's
    assert script =~ "tmux -L 'console-workspace-1'"
    assert script =~ "new-session -A -s 'w1_view' -t 'w1'"
    assert script =~ "select-window -t 'w1:3'"
    assert String.starts_with?(script, "exec ")
  end

  test "single-quotes interpolations so a name can't split the command" do
    {_bash, ["-lc", script]} = SessionPane.command("s'x y", 0)
    # an embedded apostrophe is escaped as '\'' — the value stays one shell token
    assert script =~ ~S(exec tmux -L 'console-workspace-s'\''x y')
    assert script =~ "'ws'\\''x y_view'"
  end
end
