defmodule Server.ArbiterTest do
  # The arbiter is a config-selected capability (§8): the switchboard decides who to wake, the
  # backend actuates. No backend is a valid state — the switchboard runs the durable channel
  # without a display — so wake/spawn return {:error, :no_arbiter}, never crash.
  use ExUnit.Case, async: false

  alias Server.Arbiter

  setup do
    on_exit(fn ->
      Application.delete_env(:server, :arbiter)
      Application.delete_env(:server, :test_pid)
    end)
  end

  describe "no backend configured — the honest no-op" do
    test "wake/spawn return {:error, :no_arbiter}, never raise" do
      Application.delete_env(:server, :arbiter)
      assert Arbiter.wake(%{thread_id: 1, pane_ref: "x"}, "hi") == {:error, :no_arbiter}
      assert Arbiter.spawn("export TLON_THREAD=\"1\"") == {:error, :no_arbiter}
    end
  end

  describe "the Test backend captures the switchboard's decisions" do
    setup do
      Application.put_env(:server, :arbiter, Server.Arbiter.Test)
      Application.put_env(:server, :test_pid, self())
      :ok
    end

    test "wake sends the session's pane_ref + prompt" do
      assert Arbiter.wake(%{thread_id: 7, pane_ref: "wCarl", agent: "Carl"}, "you there?") == :ok
      assert_received {:woke, "wCarl", "you there?"}
    end

    test "spawn sends the exports block" do
      assert {:ok, _} = Arbiter.spawn(~s(export TLON_THREAD="7"))
      assert_received {:spawned, ~s(export TLON_THREAD="7")}
    end
  end
end
