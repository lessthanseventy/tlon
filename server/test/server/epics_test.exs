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
end
