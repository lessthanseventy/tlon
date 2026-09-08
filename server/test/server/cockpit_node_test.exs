defmodule Server.CockpitNodeTest do
  use ExUnit.Case, async: true

  alias Server.Arbiter.Remote

  # the always-up service with no cockpit connected: every terminal-needing backend degrades to
  # {:error, :no_cockpit}, never a crash, never a hang
  test "no cockpit connected degrades honestly" do
    assert Server.CockpitNode.find() == nil
    assert Server.CockpitNode.call(Console.Arbiter, :spawn, ["x"]) == {:error, :no_cockpit}
    assert Remote.wake(%{thread_id: 1}, "hi") == {:error, :no_cockpit}
    assert Remote.spawn("exports") == {:error, :no_cockpit}
    assert Server.Crew.Remote.spawn_role("reviewer", 1, "look") == {:error, :no_cockpit}
    assert Server.Crew.Remote.kill_role("reviewer", 1) == {:error, :no_cockpit}
  end
end
