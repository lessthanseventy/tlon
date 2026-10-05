defmodule Server.StandaloneTest do
  # The standalone binary's command line (Server.Standalone): with nothing, or `serve`, it is the
  # service; `help` says so; anything else is refused, never guessed at.
  use ExUnit.Case, async: true

  alias Server.Standalone

  test "no arguments, or serve, runs the service" do
    assert Standalone.command([]) == :serve
    assert Standalone.command(["serve"]) == :serve
  end

  test "help, and an unknown command, say how to use it" do
    assert Standalone.command(["help"]) == :help
    assert Standalone.command(["--help"]) == :help
    assert Standalone.command(["frobnicate"]) == {:unknown, "frobnicate"}
  end
end
