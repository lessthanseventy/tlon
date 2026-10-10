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

    test "start_thread opens a thread on the ticket's project whose opening post is the ticket, and promotes it" do
      {:ok, ws} = Workspaces.create(%{name: "Start"})
      {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})

      {:ok, t} =
        Tickets.file(%{workspace_id: ws.id, project_id: p.id, title: "unbind ctrl+enter", body: "ghostty eats it"})

      assert {:ok, thread} = Tickets.start_thread(t)
      assert %{title: "unbind ctrl+enter", project_id: pid, workspace_id: wid, state: "open"} = thread
      assert {pid, wid} == {p.id, ws.id}

      assert [%{body: body}] = for(m <- Channel.thread_messages(thread), m.author == "andrew", do: m)
      assert body =~ "unbind ctrl+enter"
      assert body =~ "ghostty eats it"
      assert body =~ "ticket ##{t.id}"

      assert %{status: "doing"} = Tickets.get(t.id)
      assert [{"promoted", tid}] = Tickets.threads_of(t.id)
      assert tid == thread.id
    end

    test "a started ticket is a workline at build — verified, reviewed and graded like any other" do
      {:ok, ws} = Workspaces.create(%{name: "Tracked"})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "Floor step 3: build mode"})

      assert {:ok, %{stage: "build", slug: slug} = thread} = Tickets.start_thread(t)
      assert slug =~ "floor-step-3"
      assert %{stage: "build"} = Server.Repo.get!(Server.Thread, thread.id)
    end

    test "route sends a ticket to the workspace's manager as intake on its root thread" do
      {:ok, ws} = Workspaces.register(%{name: "Routed"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius-r", archetype: "surveyor"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "hronir-r", archetype: "builder"})
      {:ok, root} = Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "inbox design", body: "one inbox"})

      assert {:ok, %{routed_to: "tertius-r"}} = Tickets.route(t)
      assert %{author: "andrew", body: body} = List.last(Channel.thread_messages(root))
      assert body =~ "@tertius-r" and body =~ "ticket ##{t.id}" and body =~ "inbox design"
      assert %{status: "todo"} = Tickets.get(t.id)
    end

    test "a ticket is done when its workline merges — not when its thread is closed mid-stage" do
      {:ok, ws} = Workspaces.create(%{name: "Closing"})
      {:ok, dropped} = Tickets.file(%{workspace_id: ws.id, title: "abandoned at build"})
      {:ok, shipped} = Tickets.file(%{workspace_id: ws.id, title: "ship it"})
      {:ok, at_build} = Tickets.start_thread(dropped)
      {:ok, landing} = Tickets.start_thread(shipped)

      assert {:ok, _} = Channel.close_thread(at_build)
      assert %{status: "doing"} = Tickets.get(dropped.id)

      {:ok, merged} = landing |> Server.Thread.workline_stage_changeset(%{stage: "merged"}) |> Server.Repo.update()
      assert {:ok, _} = Channel.close_thread(merged)
      assert %{status: "done"} = Tickets.get(shipped.id)
    end

    test "an unmerged workline closes by hand only with a why, and the why decides its ticket" do
      {:ok, ws} = Workspaces.create(%{name: "Why"})
      {:ok, dup} = Tickets.file(%{workspace_id: ws.id, title: "built twice"})
      {:ok, dropped} = Tickets.file(%{workspace_id: ws.id, title: "not worth it"})
      {:ok, dup_line} = Tickets.start_thread(dup)
      {:ok, dropped_line} = Tickets.start_thread(dropped)

      assert {:error, :why_closed} = Channel.close_as(dup_line, nil)
      assert {:error, :why_closed} = Channel.close_as(dup_line, {:superseded, "  "})
      assert %{state: "open"} = Server.Repo.get!(Server.Thread, dup_line.id)

      assert {:ok, %{state: "closed"}} = Channel.close_as(dup_line, {:superseded, "PR #234"})
      assert %{status: "done", body: body} = Tickets.get(dup.id)
      assert body =~ "Superseded by PR #234"
      assert List.last(Channel.thread_messages(dup_line)).body =~ "superseded by PR #234"

      assert {:ok, _} = Channel.close_as(dropped_line, {:abandoned, "the design changed"})
      assert %{status: "backlog", body: body} = Tickets.get(dropped.id)
      assert body =~ "Abandoned in workline ##{dropped_line.id}: the design changed"
    end

    test "a plain thread or a merged workline closes by hand without a why" do
      {:ok, plain} = Channel.open_thread(%{title: "a question"})
      assert {:ok, %{state: "closed"}} = Channel.close_as(plain, nil)
    end

    test "a merged workline sent back (its PR conflicted) takes its ticket back to doing" do
      {:ok, ws} = Workspaces.create(%{name: "Reland"})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "the garden tile"})
      {:ok, thread} = Tickets.start_thread(t)
      {:ok, merged} = thread |> Server.Thread.workline_stage_changeset(%{stage: "merged"}) |> Server.Repo.update()
      {:ok, _} = Channel.close_thread(merged)
      assert %{status: "done"} = Tickets.get(t.id)

      {:error, {:bounced, _}} =
        Server.Workline.reland(Server.Repo.get!(Server.Thread, thread.id), "its PR #9 conflicts")

      assert %{status: "doing"} = Tickets.get(t.id)
    end

    test "a started ticket is never left with the manager: the workline goes to a builder" do
      {:ok, ws} = Workspaces.create(%{name: "Managed"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius-m", archetype: "surveyor"})
      {:ok, builder} = Workspaces.seat(ws.id, %{name: "hronir-m", archetype: "builder"})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "build the sweep"})

      assert {:ok, %{stage: "build", agent_id: lead}} = Tickets.start_thread(t)
      assert lead == builder.agent_id
    end

    test "a started ticket on a bench with only the manager is left unled, never the manager's" do
      {:ok, ws} = Workspaces.create(%{name: "Manager only"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "tertius-o", archetype: "surveyor"})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "build the sweep"})

      assert {:ok, %{id: id, stage: "build", agent_id: nil}} = Tickets.start_thread(t)
      assert Server.Channel.thread_lead(id) == nil
    end

    test "route with no manager on the bench starts the ticket with the lead" do
      {:ok, ws} = Workspaces.create(%{name: "Unmanaged"})
      {:ok, lead} = Workspaces.seat(ws.id, %{name: "hronir-u", archetype: "builder"})
      {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: "build it"})

      assert {:ok, %{started: thread}} = Tickets.route(t)
      assert thread.agent_id == lead.agent_id
      assert %{status: "doing"} = Tickets.get(t.id)
    end

    test "start_thread staffs the named agent instead of the lead; without one, the lead" do
      {:ok, ws} = Workspaces.create(%{name: "Hand"})
      {:ok, lead} = Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})
      {:ok, orbis} = Workspaces.seat(ws.id, %{name: "orbis", archetype: "reviewer"})
      {:ok, handed} = Tickets.file(%{workspace_id: ws.id, title: "review the rail"})
      {:ok, plain} = Tickets.file(%{workspace_id: ws.id, title: "build the rail"})

      assert {:ok, %{agent_id: a}} = Tickets.start_thread(handed, orbis.agent_id)
      assert a == orbis.agent_id
      assert {:ok, %{agent_id: b}} = Tickets.start_thread(plain)
      assert b == lead.agent_id
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

  describe "board order (UX slice 4)" do
    test "a new ticket lands at the TOP of its column", %{workspace: ws} do
      {:ok, _first} = Tickets.file(%{workspace_id: ws.id, title: "first"})
      {:ok, _second} = Tickets.file(%{workspace_id: ws.id, title: "second"})

      assert ["second", "first"] = ws.id |> Tickets.in_workspace() |> Enum.map(& &1.title)
    end

    test "reorder swaps a ticket with its neighbour, and it persists", %{workspace: ws} do
      {:ok, _bottom} = Tickets.file(%{workspace_id: ws.id, title: "bottom"})
      {:ok, top} = Tickets.file(%{workspace_id: ws.id, title: "top"})

      assert ["top", "bottom"] = ws.id |> Tickets.in_workspace() |> Enum.map(& &1.title)

      assert :ok = Tickets.reorder(Tickets.get(top.id), :down)
      assert ["bottom", "top"] = ws.id |> Tickets.in_workspace() |> Enum.map(& &1.title)

      assert :ok = Tickets.reorder(Tickets.get(top.id), :up)
      assert ["top", "bottom"] = ws.id |> Tickets.in_workspace() |> Enum.map(& &1.title)
    end

    test "reordering past the end of a column is :ok, not an error", %{workspace: ws} do
      {:ok, only} = Tickets.file(%{workspace_id: ws.id, title: "only"})

      assert :ok = Tickets.reorder(only, :up)
      assert :ok = Tickets.reorder(only, :down)
    end

    test "a reorder only sees its OWN column — a neighbour in another status is not one", %{workspace: ws} do
      {:ok, a} = Tickets.file(%{workspace_id: ws.id, title: "a"})
      {:ok, b} = Tickets.file(%{workspace_id: ws.id, title: "b"})
      {:ok, _} = Tickets.update(b, %{status: "doing"})

      # `a` is alone in backlog now, so there is nothing to swap with
      assert :ok = Tickets.reorder(Tickets.get(a.id), :up)
      assert Tickets.get(a.id).sort == a.sort
    end
  end
end
