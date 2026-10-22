defmodule Server.BlockedTest do
  # A seat that cannot act because an open ticket is in the way says so once, on the ticket: no
  # operator ask, no nudges, and the ticket's close (at the next cut) wakes it.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Blocked
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Stuck"})
    {:ok, ticket} = Tickets.file(%{workspace_id: ws.id, title: "worktrees are read-only", body: "bwrap"})
    %{ws: ws, ticket: ticket}
  end

  defp seat(ws, name) do
    {:ok, agent} = Server.Staff.register_agent(%{name: name, mandate: "build", engine: "fresh"})
    {:ok, t} = Channel.open_thread(%{title: "work of #{name}", workspace_id: ws.id, agent_id: agent.id})
    t
  end

  defp posts(thread_id), do: Repo.all(from m in Message, where: m.thread_id == ^thread_id, order_by: m.id)

  describe "declare/4" do
    test "ties the thread to the ticket, appends what it saw, posts a notice and asks nobody", %{ws: ws, ticket: tk} do
      t = seat(ws, "yu")
      assert {:ok, ticket} = Blocked.declare(tk.id, t.id, "yu", "cannot write to my worktree")

      assert ticket.body =~ "Seen again (#{Date.utc_today()}, by yu, thread #{t.id}): cannot write to my worktree"
      assert Blocked.blocked?(t.id)
      assert [%Message{kind: "notice", body: body}] = posts(t.id)
      assert body =~ "##{tk.id}"
      assert Server.Attention.open_asks() == []
      assert Enum.all?(Server.Office.Needs.list(), &(&1.kind != "question"))
    end

    test "saying it twice ties once", %{ws: ws, ticket: tk} do
      t = seat(ws, "yu")
      {:ok, _} = Blocked.declare(tk.id, t.id, "yu", "first")
      {:ok, _} = Blocked.declare(tk.id, t.id, "yu", "again")
      assert [{"blocked_on", _}] = Tickets.threads_of(tk.id)
    end

    test "a done ticket, a missing one or an epic is refused", %{ws: ws, ticket: tk} do
      t = seat(ws, "yu")
      {:ok, _} = Tickets.update(tk, %{status: "done"})
      assert {:error, why} = Blocked.declare(tk.id, t.id, "yu", "x")
      assert why =~ "not open"
      assert {:error, _} = Blocked.declare(999_999, t.id, "yu", "x")
      {:ok, epic} = Tickets.file(%{workspace_id: ws.id, title: "an epic", kind: "epic"})
      assert {:error, _} = Blocked.declare(epic.id, t.id, "yu", "x")
      refute Blocked.blocked?(t.id)
    end
  end

  describe "release/1" do
    test "a blocker closed after the cut stays blocked: the fix is not in that release", %{ws: ws, ticket: tk} do
      t = seat(ws, "yu")
      {:ok, _} = Blocked.declare(tk.id, t.id, "yu", "ro")
      {:ok, _} = Tickets.update(Tickets.get(tk.id), %{status: "done"})
      before_close = DateTime.add(DateTime.utc_now(), -60)

      assert Blocked.release(before_close) == 0
      assert Blocked.blocked?(t.id)
      assert Blocked.release(DateTime.add(DateTime.utc_now(), 60)) == 1
    end

    test "a closed blocker clears the block and wakes the lead with a post that names it", %{ws: ws, ticket: tk} do
      t = seat(ws, "yu")
      {:ok, _} = Blocked.declare(tk.id, t.id, "yu", "ro")
      assert Blocked.release() == 0
      assert Blocked.blocked?(t.id)

      {:ok, _} = Tickets.update(Tickets.get(tk.id), %{status: "done"})
      assert Blocked.release() == 1
      refute Blocked.blocked?(t.id)

      %Message{kind: kind, author: "tlon", body: body} = List.last(posts(t.id))
      assert kind != "notice"
      assert body =~ "@yu"
      assert body =~ "##{tk.id}"
      assert body =~ "retry"
      assert Blocked.release() == 0
    end
  end
end
