defmodule Server.EpicsTest do
  # Epics (design 2026-10-08): a ticket of kind "epic" holds other tickets via `parent` links and is never work.
  use ExUnit.Case, async: false

  alias Server.Repo
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Epics"})
    %{ws: ws}
  end

  defp file(ws, title, attrs \\ %{}),
    do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: title}, attrs)), 1)

  defp epic(ws, title, attrs \\ %{}), do: file(ws, title, Map.put(attrs, :kind, "epic"))

  describe "kind" do
    test "defaults to ticket and can be filed as epic", %{ws: ws} do
      assert file(ws, "plain").kind == "ticket"
      assert epic(ws, "Toy").kind == "epic"
    end

    test "a kind outside the set is a changeset error, and the DB refuses it too", %{ws: ws} do
      assert {:error, cs} = Tickets.file(%{workspace_id: ws.id, title: "x", kind: "story"})
      assert {:kind, _} = List.keyfind(cs.errors, :kind, 0)

      assert_raise Postgrex.Error, ~r/ticket_kind_check/, fn ->
        Repo.query!("UPDATE ticket SET kind = 'story' WHERE id = $1", [file(ws, "y").id])
      end
    end

    test "kind cannot be changed by update", %{ws: ws} do
      t = file(ws, "plain")
      {:ok, t} = Tickets.update(t, %{kind: "epic"})
      assert t.kind == "ticket"
    end
  end

  describe "the parent law" do
    test "an epic adopts a ticket; read both ways", %{ws: ws} do
      e = epic(ws, "Toy")
      c = file(ws, "child")
      assert {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert [%{kind: "parent", direction: :out, ticket_id: cid}] = Tickets.links_of(e.id)
      assert cid == c.id
      assert [%{kind: "parent", direction: :in}] = Tickets.links_of(c.id)
    end

    test "a second parent is refused", %{ws: ws} do
      e1 = epic(ws, "One")
      e2 = epic(ws, "Two")
      c = file(ws, "child")
      {:ok, _} = Tickets.link(e1.id, c.id, "parent")
      assert {:error, cs} = Tickets.link(e2.id, c.id, "parent")
      assert {"already has a parent epic", _} = cs.errors[:to_id]
    end

    test "adopting twice into the same epic stays idempotent", %{ws: ws} do
      e = epic(ws, "Toy")
      c = file(ws, "child")
      {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert {:ok, _} = Tickets.link(e.id, c.id, "parent")
    end

    test "no epic under an epic, and only an epic is a parent", %{ws: ws} do
      outer = epic(ws, "Outer")
      inner = epic(ws, "Inner")
      plain = file(ws, "plain")
      other = file(ws, "other")
      assert {:error, cs} = Tickets.link(outer.id, inner.id, "parent")
      assert {"an epic cannot have a parent", _} = cs.errors[:to_id]
      assert {:error, cs} = Tickets.link(plain.id, other.id, "parent")
      assert {"only an epic can be a parent", _} = cs.errors[:from_id]
    end
  end

  describe "an epic is never work" do
    test "start_thread and route refuse it", %{ws: ws} do
      e = epic(ws, "Toy")
      assert {:error, :epic} = Tickets.start_thread(e)
      assert {:error, :epic} = Tickets.route(e)
      assert Tickets.get(e.id).status == "backlog"
    end
  end
end
