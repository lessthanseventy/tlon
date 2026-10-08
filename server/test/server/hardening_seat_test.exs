defmodule Server.HardeningSeatTest do
  # A seat's archetype resolves against the role registry; one it can't resolve (a typo, "Builder")
  # was stored anyway and crashed every read that instantiates the seat's profile (presence, the
  # office snapshot, the switchboard). It is refused when written.
  use ExUnit.Case, async: false

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "an unknown archetype is refused when the seat is written; a known one is seated" do
    {:ok, ws} = Server.Workspaces.create(%{name: "Seats"})
    assert {:error, _} = Server.Workspaces.seat(ws.id, %{name: "typo", archetype: "Builder"})
    assert {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "fine", archetype: "builder"})
  end
end
