defmodule Server.MCP.ToolTest do
  use ExUnit.Case, async: false

  alias Server.MCP.Tool
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "a seat's cut list is read once per TTL: a re-seat inside it reads the cached list, after it the new one" do
    {:ok, ws} = Workspaces.register(%{name: "Fence cache"})
    {:ok, seat} = Workspaces.seat(ws.id, %{name: "hladik", archetype: "builder"})
    t0 = System.monotonic_time(:millisecond)

    builder_cut = Tool.cut_tools(ws.id, "hladik", t0)
    assert "submit_qa" in builder_cut

    {:ok, _} = Workspaces.unseat(seat.id)
    {:ok, _} = Workspaces.seat(ws.id, %{name: "hladik", archetype: "qa"})

    assert Tool.cut_tools(ws.id, "hladik", t0 + 1) == builder_cut
    refute "submit_qa" in Tool.cut_tools(ws.id, "hladik", t0 + 60_000)
  end

  test "a name with no seat on the workspace has no cut list" do
    {:ok, ws} = Workspaces.register(%{name: "Fence none"})
    assert Tool.cut_tools(ws.id, "nobody") == []
  end
end
