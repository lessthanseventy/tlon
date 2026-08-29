defmodule Server.CrewTest do
  # Crew is a config-selected capability, the same seam as the arbiter (§8): funes decides a role
  # should be staffed onto a thread, an injected backend actuates (aleph spawns the tmux window). No
  # backend is a valid state — the always-up service has no crew to spawn — so spawn/kill return
  # {:error, :no_crew}, never crash.
  use ExUnit.Case, async: false

  alias Server.Crew

  setup do
    on_exit(fn ->
      Application.delete_env(:server, :crew)
      Application.delete_env(:server, :test_pid)
    end)
  end

  describe "no backend configured — the honest no-op" do
    test "spawn_role/kill_role return {:error, :no_crew}, never raise" do
      Application.delete_env(:server, :crew)
      assert Crew.spawn_role("reviewer", 1, "review HEAD~1") == {:error, :no_crew}
      assert Crew.kill_role("reviewer", 1) == {:error, :no_crew}
    end
  end

  describe "the Test backend captures the orchestrator's decisions" do
    setup do
      Application.put_env(:server, :crew, Server.Crew.Test)
      Application.put_env(:server, :test_pid, self())
      :ok
    end

    test "spawn_role dispatches role + thread + task to the backend" do
      assert {:ok, "r7"} = Crew.spawn_role("reviewer", 7, "review the diff")
      assert_received {:crew_spawn, "reviewer", 7, "review the diff"}
    end

    test "kill_role dispatches role + thread to the backend" do
      assert :ok = Crew.kill_role("reviewer", 7)
      assert_received {:crew_kill, "reviewer", 7}
    end
  end
end
