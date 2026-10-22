defmodule Server.InitiativesTest do
  # Initiatives: a ticket of kind "initiative" holds epics as an epic holds tickets — never work, its
  # status derived from its epics', and a ticket moves between parents in one call.
  use ExUnit.Case, async: false

  alias Server.Repo
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Initiatives"})
    %{ws: ws}
  end

  defp file(ws, title, attrs \\ %{}), do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: title}, attrs)), 1)
  defp epic(ws, title, attrs \\ %{}), do: file(ws, title, Map.put(attrs, :kind, "epic"))
  defp initiative(ws, title), do: file(ws, title, %{kind: "initiative"})
  defp status(t), do: Tickets.get(t.id).status

  describe "the parent law, one level up" do
    test "an initiative holds epics; an epic is filed straight under one", %{ws: ws} do
      i = initiative(ws, "Kids")
      e = epic(ws, "Toy")
      assert {:ok, _} = Tickets.link(i.id, e.id, "parent")
      assert Tickets.epic_of(e.id) == i.id
      assert {:ok, e2} = Tickets.file(%{workspace_id: ws.id, title: "Hall", kind: "epic", epic_id: i.id})
      assert Tickets.epic_of(e2.id) == i.id
    end

    test "an initiative holds no ticket, has no parent, and an epic's parent is only an initiative", %{ws: ws} do
      i = initiative(ws, "Kids")
      other = initiative(ws, "Engine")
      e = epic(ws, "Toy")
      e2 = epic(ws, "Hall")
      t = file(ws, "plain")

      assert {:error, cs} = Tickets.link(i.id, t.id, "parent")
      assert {"an initiative holds epics, not tickets", _} = cs.errors[:to_id]
      assert {:error, cs} = Tickets.link(other.id, i.id, "parent")
      assert {"an initiative cannot have a parent", _} = cs.errors[:to_id]
      assert {:error, cs} = Tickets.link(e.id, e2.id, "parent")
      assert {"an epic's parent can only be an initiative", _} = cs.errors[:to_id]
    end
  end

  describe "an initiative is never work" do
    test "start_thread, route and claim refuse it; intake never picks it", %{ws: ws} do
      i = initiative(ws, "Kids")
      assert {:error, :initiative} = Tickets.start_thread(i)
      assert {:error, :initiative} = Tickets.route(i)
      assert {:error, :initiative} = Tickets.claim(i, "emma")
      assert Server.Intake.next(ws.id) == nil
    end

    test "its status is not set by hand", %{ws: ws} do
      i = initiative(ws, "Kids")
      {:ok, _} = Tickets.update(i, %{status: "doing"})
      assert status(i) == "backlog"
    end
  end

  test "an initiative's status follows its epics, which follow their tickets", %{ws: ws} do
    i = initiative(ws, "Kids")
    [e1, e2] = for t <- ["Toy", "Hall"], do: epic(ws, t)
    [a, b] = for t <- ["a", "b"], do: file(ws, t)
    for e <- [e1, e2], do: {:ok, _} = Tickets.link(i.id, e.id, "parent")
    {:ok, _} = Tickets.link(e1.id, a.id, "parent")
    {:ok, _} = Tickets.link(e2.id, b.id, "parent")

    assert status(i) == "backlog"
    {:ok, a} = Tickets.update(a, %{status: "doing"})
    assert status(e1) == "doing" and status(i) == "doing"
    {:ok, _} = Tickets.update(a, %{status: "done"})
    assert status(e1) == "done" and status(i) == "doing"
    {:ok, _} = Tickets.update(b, %{status: "done"})
    assert status(e2) == "done" and status(i) == "done"
  end

  describe "moving a ticket to another parent" do
    test "it leaves the old epic and joins the new, and both re-derive", %{ws: ws} do
      [from, to] = for t <- ["From", "To"], do: epic(ws, t)
      a = file(ws, "a")
      {:ok, a} = Tickets.update(a, %{status: "doing"})
      {:ok, _} = Tickets.link(from.id, a.id, "parent")
      assert status(from) == "doing"

      assert {:ok, _} = Tickets.move(a.id, to.id)
      assert Tickets.epic_of(a.id) == to.id
      assert status(from) == "backlog" and status(to) == "doing"
    end

    test "nil makes it loose; a refused parent leaves it where it was", %{ws: ws} do
      e = epic(ws, "Toy")
      a = file(ws, "a")
      {:ok, _} = Tickets.link(e.id, a.id, "parent")
      plain = file(ws, "plain")

      assert {:error, _} = Tickets.move(a.id, plain.id)
      assert Tickets.epic_of(a.id) == e.id
      assert {:ok, _} = Tickets.move(a.id, nil)
      assert Tickets.epic_of(a.id) == nil
      assert Repo.aggregate(Server.TicketLink, :count) == 0
    end
  end
end
