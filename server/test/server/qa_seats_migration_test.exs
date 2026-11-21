defmodule Server.QaSeatsMigrationTest do
  # A seat cast as the retired qa archetype becomes a builder: a data move, once, through the
  # migration that boots with the release. Run here again at a version of its own; test_helper's
  # migrate has already loaded the module.
  use ExUnit.Case, async: false

  alias Server.Workspaces

  @version 99_000_101_000_002

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Server.Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@version]) end)
    :ok
  end

  defp archetype(ws, name), do: ws.id |> Workspaces.bench() |> Enum.find(&(&1.name == name)) |> Map.get(:archetype)

  test "a qa seat becomes a builder; every other seat is left as it is" do
    roster = [%{"archetype" => "builder", "name" => "nolan"}, %{"archetype" => "reviewer", "name" => "lonnrot"}]
    {:ok, ws} = Workspaces.register(%{name: "Machine", roster: roster})

    Server.Repo.query!(
      "UPDATE workspace_agent wa SET archetype = 'qa' FROM agent a WHERE wa.agent_id = a.id AND a.name = 'nolan'"
    )

    :ok = Ecto.Migrator.up(Server.Repo, @version, Server.Repo.Migrations.QaSeatsAreBuilders, log: false)

    assert archetype(ws, "nolan") == "builder"
    assert archetype(ws, "lonnrot") == "reviewer"
  end
end
