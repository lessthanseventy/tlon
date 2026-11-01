defmodule Server.Jobs.LandTest do
  use ExUnit.Case, async: true

  alias Server.Jobs.Land

  test "a gate killed by a signal is interrupted, not red; one that ran and failed is red" do
    assert {:error, {:interrupted, why}} = Land.gate_result({"Terminated", 143})
    assert why =~ "143"
    assert {:error, {:interrupted, _}} = Land.gate_result({"", 137})
    assert {:error, red} = Land.gate_result({"1 failure", 1})
    assert is_binary(red) and red =~ "red"
    assert {:ok, :green} = Land.gate_result({"", 0})
  end

  test "a gate whose BEAM was SIGTERMed is interrupted even when the wrapper exits 1" do
    out = "[server:check] SIGTERM received - shutting down\n** (EXIT from #PID<0.95.0>) shutdown\n"
    assert {:error, {:interrupted, _}} = Land.gate_result({out, 1})
  end

  test "the SIGTERM phrase quoted mid-line (a failing test's report) is still red" do
    out =
      "right: {:error, \"the full check is red (exit 1): [server:check] SIGTERM received - shutting down\\n** (EXIT from #PID<0.95.0>) shutdown\"}\n"

    assert {:error, why} = Land.gate_result({out, 1})
    assert is_binary(why)
  end

  test "one landing per workline and one per PR branch: a PR's job never collides with another's" do
    assert %{changes: %{unique: %{keys: [:thread_id, :branch]}}} = Land.new(%{"pr" => 7, "branch" => "x"})
  end

  test "a landing is tried three times" do
    assert %{changes: %{max_attempts: 3}} = Land.new(%{thread_id: 1})
  end
end
