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

  test "a landing is tried three times" do
    assert %{changes: %{max_attempts: 3}} = Land.new(%{thread_id: 1})
  end
end
