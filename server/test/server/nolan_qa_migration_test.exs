defmodule Server.NolanQaMigrationTest do
  # Roster design §5: nolan leaves the builders to be the Machine workspace's QA — a data move,
  # once, through the migration that boots with the release. Run here again at a version of its own;
  # test_helper's migrate has already loaded the module.
  use ExUnit.Case, async: false

  alias Server.Workspaces

  @version 99_000_101_000_001

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Server.Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@version]) end)
    %{mod: Server.Repo.Migrations.NolanIsQa}
  end

  defp seat!(name, roster), do: elem(Workspaces.register(%{name: name, roster: roster}), 1)
  defp archetype(ws, name), do: ws.id |> Workspaces.bench() |> Enum.find(&(&1.name == name)) |> Map.get(:archetype)

  test "nolan the builder on the Machine bench becomes its qa; nobody else, nowhere else", %{mod: mod} do
    machine =
      seat!("Machine", [%{"archetype" => "builder", "name" => "nolan"}, %{"archetype" => "builder", "name" => "emma"}])

    other = seat!("Elsewhere", [%{"archetype" => "builder", "name" => "nolan"}])

    :ok = Ecto.Migrator.up(Server.Repo, @version, mod, log: false)

    assert archetype(machine, "nolan") == "qa"
    assert archetype(machine, "emma") == "builder"
    assert archetype(other, "nolan") == "builder"
  end

  test "a bench with no nolan is left as it is", %{mod: mod} do
    machine = seat!("Machine", [%{"archetype" => "builder", "name" => "hronir"}])
    :ok = Ecto.Migrator.up(Server.Repo, @version, mod, log: false)
    assert archetype(machine, "hronir") == "builder"
  end
end
