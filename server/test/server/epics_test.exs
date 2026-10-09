defmodule Server.EpicsTest do
  # Epics (design 2026-10-08): a ticket of kind "epic" holds other tickets via `parent` links and is never work.
  use ExUnit.Case, async: false

  alias Server.Intake
  alias Server.Repo
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Epics"})
    %{ws: ws}
  end

  defp file(ws, title, attrs \\ %{}), do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: title}, attrs)), 1)

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

    test "an epic's status cannot be set by hand; a ticket's still can", %{ws: ws} do
      e = epic(ws, "Toy")
      {:ok, e} = Tickets.update(e, %{status: "done", title: "Renamed"})
      assert e.status == "backlog"
      assert e.title == "Renamed"
      assert {:ok, %{status: "doing"}} = Tickets.update(file(ws, "plain"), %{status: "doing"})
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

    test "the DB refuses a second parent even if the changeset check is raced past", %{ws: ws} do
      [e1, e2] = [epic(ws, "One"), epic(ws, "Two")]
      c = file(ws, "child")
      {:ok, _} = Tickets.link(e1.id, c.id, "parent")

      assert_raise Postgrex.Error, ~r/ticket_link_one_parent/, fn ->
        Repo.query!("INSERT INTO ticket_link (from_id, to_id, kind, created_at) VALUES ($1, $2, 'parent', now())", [
          e2.id,
          c.id
        ])
      end
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

  describe "derived epic status" do
    setup %{ws: ws} do
      e = epic(ws, "Toy")
      [a, b] = for t <- ["a", "b"], do: file(ws, t)
      for c <- [a, b], do: {:ok, _} = Tickets.link(e.id, c.id, "parent")
      %{e: e, a: a, b: b}
    end

    defp status(e), do: Tickets.get(e.id).status

    test "backlog until a child starts, doing after, done when the last child closes", %{e: e, a: a, b: b} do
      assert status(e) == "backlog"
      {:ok, a} = Tickets.update(a, %{status: "todo"})
      assert status(e) == "backlog"
      {:ok, a} = Tickets.update(a, %{status: "doing"})
      assert status(e) == "doing"
      {:ok, _} = Tickets.update(a, %{status: "done"})
      assert status(e) == "doing"
      {:ok, _} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      assert Tickets.get(e.id).closed_at
    end

    test "promote starts the epic; a reopened or added child sends it back to doing", %{ws: ws, e: e, a: a, b: b} do
      {:ok, _} = Tickets.update(a, %{status: "done"})
      {:ok, b} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      {:ok, b} = Tickets.update(b, %{status: "doing"})
      assert status(e) == "doing"
      {:ok, _} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      c = file(ws, "late addition")
      {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert status(e) == "doing"
      Tickets.remove(c)
      assert status(e) == "done"
    end

    test "unlinking the only unfinished child can close the epic; an epic with no children is backlog",
         %{ws: ws, e: e, a: a, b: b} do
      {:ok, _} = Tickets.update(a, %{status: "done"})
      :ok = Tickets.unlink(e.id, b.id, "parent")
      assert status(e) == "done"
      :ok = Tickets.unlink(e.id, a.id, "parent")
      assert status(e) == "backlog"
      assert status(epic(ws, "Empty")) == "backlog"
    end
  end

  describe "intake" do
    defp adopt(e, c), do: {:ok, _} = Tickets.link(e.id, c.id, "parent")

    test "never picks an epic", %{ws: ws} do
      epic(ws, "Toy", %{priority: "high"})
      assert Intake.next(ws.id) == nil
    end

    test "a child inherits a high epic over a med loose ticket", %{ws: ws} do
      e = epic(ws, "Toy", %{priority: "high"})
      c = file(ws, "child")
      adopt(e, c)
      file(ws, "loose newer")
      assert Intake.next(ws.id).id == c.id
    end

    test "an epic's own priority never lowers a child's", %{ws: ws} do
      e = epic(ws, "Toy", %{priority: "low"})
      c = file(ws, "child", %{priority: "high"})
      adopt(e, c)
      file(ws, "loose", %{priority: "med"})
      assert Intake.next(ws.id).id == c.id
    end

    test "within an epic the lowest sort goes first, not the newest", %{ws: ws} do
      e = epic(ws, "Toy")
      first = file(ws, "step 1", %{sort: 1})
      second = file(ws, "step 2", %{sort: 2})
      third = file(ws, "step 3", %{sort: 3})
      for c <- [third, first, second], do: adopt(e, c)
      assert Intake.next(ws.id).id == first.id
      {:ok, _} = Tickets.update(first, %{status: "done"})
      assert Intake.next(ws.id).id == second.id
    end

    test "equally urgent: the child of a doing epic beats a newer loose ticket and an unstarted epic's child",
         %{ws: ws} do
      started = epic(ws, "Started")
      started_done = file(ws, "s1", %{sort: 1})
      started_next = file(ws, "s2", %{sort: 2})
      adopt(started, started_done)
      adopt(started, started_next)
      {:ok, _} = Tickets.update(started_done, %{status: "done"})
      assert Tickets.get(started.id).status == "doing"

      fresh = epic(ws, "Fresh")
      adopt(fresh, file(ws, "f1", %{sort: 99}))
      file(ws, "loose newest", %{sort: 100})

      assert Intake.next(ws.id).id == started_next.id
    end

    test "loose tickets keep newest-first and a blocked step is skipped", %{ws: ws} do
      file(ws, "old")
      new = file(ws, "new")
      assert Intake.next(ws.id).id == new.id

      e = epic(ws, "Toy", %{priority: "high"})
      s1 = file(ws, "s1", %{sort: 1})
      s2 = file(ws, "s2", %{sort: 2})
      adopt(e, s1)
      adopt(e, s2)
      {:ok, _} = Tickets.link(s1.id, s2.id, "blocks")
      assert Intake.next(ws.id).id == s1.id
    end
  end
end
