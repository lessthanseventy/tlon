defmodule Console.SessionPaneTest do
  # The launch spec for the toggleable right session pane (2026-08-31): a grouped tmux client pinned
  # to the selected thread's lead window. Only the command SHAPE is asserted here — the live attach
  # semantics (grouping, resize) are Andrew's kitty pass.
  use ExUnit.Case, async: true

  alias Console.SessionPane

  test "command builds a grouped, window-pinned tmux attach for the lead window" do
    assert {"/bin/bash", ["-lc", script]} = SessionPane.command(1, 3, 9)

    # a grouped session (-t w1) so the pane keeps its own current window, then selects the lead's
    assert script =~ "tmux -L 'console-workspace-1'"
    assert script =~ "new-session -A -s 'w1_view_9' -t 'w1'"
    assert script =~ "select-window -t 'w1:3'"
    assert String.starts_with?(script, "exec ")
  end

  test "the view session is PER THREAD — two open threads never share a current window" do
    {_bash, ["-lc", a]} = SessionPane.command(1, 3, 9)
    {_bash, ["-lc", b]} = SessionPane.command(1, 4, 10)

    # `-A` attaches to the named view session; one name for the whole workspace meant thread B's
    # select-window moved thread A's pane too (A then showed B's coworker).
    assert a =~ "-s 'w1_view_9'"
    assert b =~ "-s 'w1_view_10'"
  end

  test "single-quotes interpolations so a name can't split the command" do
    {_bash, ["-lc", script]} = SessionPane.command("s'x y", 0, 9)
    # an embedded apostrophe is escaped as '\'' — the value stays one shell token
    assert script =~ ~S(exec tmux -L 'console-workspace-s'\''x y')
    assert script =~ "'ws'\\''x y_view_9'"
  end
end
