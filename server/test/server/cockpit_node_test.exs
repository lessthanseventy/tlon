defmodule Server.CockpitNodeTest do
  use ExUnit.Case, async: false

  alias Server.Arbiter.Remote

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # The always-up service with no cockpit connected (one-brain piece B, slice 1): the CockpitNode
  # call itself degrades to {:error, :no_cockpit}, and the arbiter falls THROUGH to the server's
  # own tmux backend — so its errors are the backend's typed ones, never a crash, never a hang.
  # The crew backend still needs the console's profiles and keeps the old degrade.
  test "no cockpit connected: the arbiter falls back to the server's tmux backend, crew degrades honestly" do
    assert Server.CockpitNode.find() == nil
    assert Server.CockpitNode.call(Console.Arbiter, :spawn, ["x"]) == {:error, :no_cockpit}
    Application.put_env(:server, :tmux_cmd, fn "tmux", _args, _opts -> {"", 1} end)
    on_exit(fn -> Application.delete_env(:server, :tmux_cmd) end)
    assert Remote.wake(%{thread_id: 999_999}, "hi") == {:error, :no_thread}
    assert Remote.spawn("exports") == {:error, :no_identity_in_exports}
    assert Server.Crew.Remote.spawn_role("reviewer", 1, "look") == {:error, :no_cockpit}
    assert Server.Crew.Remote.kill_role("reviewer", 1) == {:error, :no_cockpit}
  end
end
