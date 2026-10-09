defmodule Server.BeatrizPmMigrationTest do
  # Roster design §5: beatriz leaves the planners to be the Machine workspace's PM — a data move,
  # once, through the migration that boots with the release. Run here again at a version of its own;
  # test_helper's migrate has already loaded the module.
  use ExUnit.Case, async: false

  alias Server.Workspaces

  @version 99_000_101_000_000

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Server.Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@version]) end)
    %{mod: Server.Repo.Migrations.BeatrizIsThePm}
  end

  defp seat!(name, roster), do: elem(Workspaces.register(%{name: name, roster: roster}), 1)
  defp archetype(ws, name), do: ws.id |> Workspaces.bench() |> Enum.find(&(&1.name == name)) |> Map.get(:archetype)

  test "beatriz the planner on the Machine bench becomes its pm; nobody else, nowhere else", %{mod: mod} do
    machine =
      seat!("Machine", [%{"archetype" => "planner", "name" => "beatriz"}, %{"archetype" => "planner", "name" => "yu"}])

    other = seat!("Elsewhere", [%{"archetype" => "planner", "name" => "beatriz"}])

    :ok = Ecto.Migrator.up(Server.Repo, @version, mod, log: false)

    assert archetype(machine, "beatriz") == "pm"
    assert archetype(machine, "yu") == "planner"
    assert archetype(other, "beatriz") == "planner"
  end

  test "a bench with no beatriz is left as it is", %{mod: mod} do
    machine = seat!("Machine", [%{"archetype" => "builder", "name" => "hronir"}])
    :ok = Ecto.Migrator.up(Server.Repo, @version, mod, log: false)
    assert archetype(machine, "hronir") == "builder"
  end
end
