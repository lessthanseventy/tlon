defmodule Console.LazygitTest do
  # The lazygit launch spec: pure command construction (its doctests); the cockpit owns the PTY.
  use ExUnit.Case, async: true

  alias Console.Lazygit

  doctest Console.Lazygit

  describe "available?/0" do
    test "reports whether lazygit is on PATH as a boolean" do
      assert is_boolean(Lazygit.available?())
    end
  end
end
