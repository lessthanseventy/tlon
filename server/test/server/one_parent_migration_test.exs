defmodule Server.OneParentMigrationTest do
  # The one-parent rule gets a partial unique index; rows written before it may already break the rule.
  # The migration keeps each child's earliest parent link and drops the rest, then adds the index.
  use ExUnit.Case, async: false

  alias Server.Repo
  alias Server.Tickets

  @version 99_000_102_000_001

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Repo.query!("DELETE FROM schema_migrations WHERE version = $1", [@version]) end)
    %{mod: Server.Repo.Migrations.OneParentIndex}
  end

  test "duplicate parent links are resolved to the earliest, then the index holds", %{mod: mod} do
    {:ok, ws} = Server.Workspaces.create(%{name: "Dupes"})
    mk = fn attrs -> elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: "t"}, attrs)), 1) end
    [e1, e2] = [mk.(%{kind: "epic"}), mk.(%{kind: "epic"})]
    c = mk.(%{})

    Repo.query!("DROP INDEX ticket_link_one_parent")

    for e <- [e1, e2],
        do:
          Repo.query!("INSERT INTO ticket_link (from_id, to_id, kind, created_at) VALUES ($1, $2, 'parent', now())", [
            e.id,
            c.id
          ])

    :ok = Ecto.Migrator.up(Repo, @version, mod, log: false)

    assert %{rows: [[1, from]]} =
             Repo.query!("SELECT count(*)::int, min(from_id) FROM ticket_link WHERE kind = 'parent'")

    assert from == e1.id

    assert_raise Postgrex.Error, ~r/ticket_link_one_parent/, fn ->
      Repo.query!("INSERT INTO ticket_link (from_id, to_id, kind, created_at) VALUES ($1, $2, 'parent', now())", [
        e2.id,
        c.id
      ])
    end
  end
end
