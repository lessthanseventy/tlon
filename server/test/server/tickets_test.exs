defmodule Server.TicketsTest do
  # The `Server.Tickets` context (2026-08-30): the lightweight terminal tracker, write pipe +
  # reads over the `local` backend.
  use ExUnit.Case, async: false

  alias Server.Bus
  alias Server.Channel
  alias Server.Ticket
  alias Server.Tickets
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Work"})
    {:ok, workspace: ws}
  end

  describe "file/1" do
    test "files a backlog ticket and announces", %{workspace: ws} do
      Bus.subscribe_tickets()
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "auth is fucked"})
      assert %Ticket{status: "backlog", priority: "med", backend: "local"} = t
      assert t.title == "auth is fucked"
      assert_receive {:ticket_filed, %Ticket{title: "auth is fucked"}}
    end

    test "workspace_id + title are required", %{workspace: ws} do
      assert {:error, %Ecto.Changeset{}} = Tickets.file(%{workspace_id: ws.id})
      assert {:error, %Ecto.Changeset{}} = Tickets.file(%{title: "x"})
    end

    test "a bad status/priority fails as a changeset, not a raise", %{workspace: ws} do
      assert {:error, %Ecto.Changeset{}} = Tickets.file(%{workspace_id: ws.id, title: "x", status: "frozen"})
      assert {:error, %Ecto.Changeset{}} = Tickets.file(%{workspace_id: ws.id, title: "x", priority: "urgent"})
    end
  end

  describe "reads" do
    test "in_workspace newest-first; open_in_workspace hides done", %{workspace: ws} do
      {:ok, a} = Tickets.file(%{workspace_id: ws.id, title: "a"})
      {:ok, b} = Tickets.file(%{workspace_id: ws.id, title: "b"})
      {:ok, _} = Tickets.update(b, %{status: "done"})

      assert Enum.map(Tickets.in_workspace(ws.id), & &1.id) == [b.id, a.id]
      assert Enum.map(Tickets.open_in_workspace(ws.id), & &1.id) == [a.id]
    end
  end

  describe "update/2, promote/2, remove/1" do
    test "update changes status + re-stamps, announces", %{workspace: ws} do
      Bus.subscribe_tickets()
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "x"})
      {:ok, moved} = Tickets.update(t, %{status: "todo", priority: "high"})
      assert moved.status == "todo"
      assert moved.priority == "high"
      assert_receive {:ticket_updated, %Ticket{status: "todo"}}
    end

    test "promote links the ticket to a thread and moves it to doing", %{workspace: ws} do
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "build the thing"})
      {:ok, thread} = Channel.open_thread(%{title: "build the thing", workspace_id: ws.id})
      {:ok, promoted} = Tickets.promote(t, thread.id)

      assert promoted.status == "doing"
      # UX slice 4: the tie is a ticket_thread row of kind `promoted`, not a column — a ticket can
      # be tied to several threads, so there is nowhere on the ticket to put one.
      assert Tickets.threads_of(t.id) == [{"promoted", thread.id}]
    end

    test "remove deletes and announces", %{workspace: ws} do
      Bus.subscribe_tickets()
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "temp"})
      assert {:ok, _} = Tickets.remove(t)
      assert Tickets.get(t.id) == nil
      assert_receive {:ticket_removed, %Ticket{}}
    end
  end

  describe "links and ties (UX slice 4)" do
    setup %{workspace: ws} do
      {:ok, a} = Tickets.file(%{workspace_id: ws.id, title: "a"})
      {:ok, b} = Tickets.file(%{workspace_id: ws.id, title: "b"})
      {:ok, a: a, b: b}
    end

    test "blocked-by is the INVERSE read of blocks, not a second row", %{a: a, b: b} do
      {:ok, _} = Tickets.link(a.id, b.id, "blocks")

      # one row, read from both ends
      assert [%{kind: "blocks", direction: :out, ticket_id: to}] = Tickets.links_of(a.id)
      assert to == b.id
      assert [%{kind: "blocks", direction: :in, ticket_id: from}] = Tickets.links_of(b.id)
      assert from == a.id

      assert Tickets.blockers(b.id) == [a.id]
      assert Tickets.blockers(a.id) == []
    end

    test "a DONE blocker stops blocking — a finished ticket blocks nothing", %{a: a, b: b} do
      {:ok, _} = Tickets.link(a.id, b.id, "blocks")
      assert Tickets.blockers(b.id) == [a.id]

      {:ok, _} = Tickets.update(a, %{status: "done"})
      assert Tickets.blockers(b.id) == []
    end

    test "blocked_in_workspace answers the whole board in one query", %{workspace: ws, a: a, b: b} do
      {:ok, _} = Tickets.link(a.id, b.id, "blocks")
      blocked = Tickets.blocked_in_workspace(ws.id)

      assert MapSet.member?(blocked, b.id)
      refute MapSet.member?(blocked, a.id)
    end

    test "a ticket cannot link to itself", %{a: a} do
      assert {:error, changeset} = Tickets.link(a.id, a.id, "blocks")
      assert {:to_id, {"a ticket cannot link to itself", _}} = List.keyfind(changeset.errors, :to_id, 0)
    end

    test "linking twice is idempotent, not an error", %{a: a, b: b} do
      {:ok, _} = Tickets.link(a.id, b.id, "relates")
      assert {:ok, _} = Tickets.link(a.id, b.id, "relates")
      assert length(Tickets.links_of(a.id)) == 1
    end

    test "unlink removes it; one that was never there is still :ok", %{a: a, b: b} do
      {:ok, _} = Tickets.link(a.id, b.id, "blocks")
      assert :ok = Tickets.unlink(a.id, b.id, "blocks")
      assert Tickets.links_of(a.id) == []
      assert :ok = Tickets.unlink(a.id, b.id, "blocks")
    end

    test "a ticket ties to MANY threads, promoted first", %{workspace: ws, a: a} do
      {:ok, one} = Channel.open_thread(%{title: "one", workspace_id: ws.id})
      {:ok, two} = Channel.open_thread(%{title: "two", workspace_id: ws.id})

      {:ok, _} = Tickets.tie(a, two.id, "relates")
      {:ok, _} = Tickets.promote(a, one.id)

      assert Tickets.threads_of(a.id) == [{"promoted", one.id}, {"relates", two.id}]
      assert Tickets.tickets_of_thread(two.id) == [{"relates", a.id}]
    end

    test "closed_at follows status: done stamps it, leaving done clears it", %{a: a} do
      assert a.closed_at == nil

      {:ok, done} = Tickets.update(a, %{status: "done"})
      assert done.closed_at

      {:ok, reopened} = Tickets.update(done, %{status: "todo"})
      assert reopened.closed_at == nil
    end
  end
end
