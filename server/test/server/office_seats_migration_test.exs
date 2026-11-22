defmodule Server.OfficeSeatsMigrationTest do
  # Run again at a version of its own; test_helper's migrate has already loaded the module.
  use ExUnit.Case, async: false

  alias Server.Workspaces

  @version 99_000_101_000_003

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Server.Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@version]) end)
    :ok
  end

  defp specialty(ws, name), do: ws.id |> Workspaces.bench() |> Enum.find(&(&1.name == name)) |> Map.get(:specialty)

  test "an office seat becomes a house seat; every other seat is left as it is" do
    {:ok, ws} = Workspaces.register(%{name: "Machine", roster: []})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "daneri", archetype: "builder", specialty: "office"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "nolan", archetype: "builder", specialty: "server"})
    {:ok, _} = Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})

    :ok = Ecto.Migrator.up(Server.Repo, @version, Server.Repo.Migrations.OfficeSeatsAreHouse, log: false)

    assert specialty(ws, "daneri") == "house"
    assert specialty(ws, "nolan") == "server"
    assert specialty(ws, "lonnrot") == nil
  end
end
