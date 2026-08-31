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
      assert promoted.promoted_thread_id == thread.id
      assert promoted.status == "doing"
    end

    test "remove deletes and announces", %{workspace: ws} do
      Bus.subscribe_tickets()
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "temp"})
      assert {:ok, _} = Tickets.remove(t)
      assert Tickets.get(t.id) == nil
      assert_receive {:ticket_removed, %Ticket{}}
    end
  end
end
