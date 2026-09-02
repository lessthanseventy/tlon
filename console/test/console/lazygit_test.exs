defmodule Console.LazygitTest do
  # The STACK-zoom lazygit launch spec (Slice 4). Pure command construction — the cockpit owns the
  # PTY lifecycle; this module just says HOW to run lazygit in a worktree.
  use ExUnit.Case, async: true

  alias Console.Lazygit

  describe "command/1" do
    test "runs lazygit in cwd via a login shell, exec'd so its quit ends the pane" do
      assert {"/bin/bash", ["-lc", script]} = Lazygit.command("/home/andrew/projects/ficciones")
      assert script == "cd '/home/andrew/projects/ficciones' && exec lazygit"
    end

    test "shell-quotes a path with spaces so cd doesn't split it" do
      assert {"/bin/bash", ["-lc", script]} = Lazygit.command("/tmp/a dir/wt")
      assert script == "cd '/tmp/a dir/wt' && exec lazygit"
    end

    test "a single quote in the path can't break out of the quoting" do
      assert {"/bin/bash", ["-lc", script]} = Lazygit.command("/tmp/it's")
      assert script == "cd '/tmp/it'\\''s' && exec lazygit"
    end
  end

  describe "available?/0" do
    test "reports whether lazygit is on PATH as a boolean" do
      assert is_boolean(Lazygit.available?())
    end
  end
end
