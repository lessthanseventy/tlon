defmodule Console.OrchestratorTest do
  @moduledoc """
  The tertius command line's dispatch. Drives the real `Server` contexts, so it boots a scratch
  db through `Console.TestRepo` → `async: false`.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Console.Orchestrator
  alias Server.Channel
  alias Server.Repo
  alias Server.Staff
  alias Server.Tickets
  alias Server.Workspaces

  setup_all do
    Console.TestRepo.boot!("orchestrator")

    :ok
  end

  setup do
    Console.TestRepo.clean!()

    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, workspace_id: ws.id, ctx: %{workspace_id: ws.id, operator: "andrew"}}
  end

  describe "classify/1" do
    test "open + approve are consequential; the rest are safe" do
      assert Orchestrator.classify({:open, "build", "x"}) == :consequential
      assert Orchestrator.classify({:approve, 5}) == :consequential
      assert Orchestrator.classify({:ticket, "x"}) == :safe
      assert Orchestrator.classify({:note, "x"}) == :safe
      assert Orchestrator.classify({:post, "h", "b"}) == :safe
    end
  end

  describe "dispatch — safe verbs" do
    test "ticket files into the workspace and reports a receipt", %{ctx: ctx, workspace_id: ws} do
      assert {:ok, receipt} = Orchestrator.dispatch({:ticket, "auth is fucked"}, ctx)
      assert receipt =~ "filed ticket #"
      assert [%{title: "auth is fucked", status: "backlog"}] = Tickets.in_workspace(ws)
    end

    test "note writes a workspace-scoped note with a receipt", %{ctx: ctx, workspace_id: ws} do
      assert {:ok, receipt} = Orchestrator.dispatch({:note, "leads are managers"}, ctx)
      assert receipt =~ "noted #"

      assert [%{body: "leads are managers", scope: "workspace", scope_id: ^ws}] =
               Server.Notes.for_scope("workspace", ws)
    end

    test "post to a coworker leading a thread posts + names the wake", %{ctx: ctx, workspace_id: ws} do
      {:ok, agent} = Staff.register_agent(%{name: "hronir", mandate: "build", engine: "fresh"})
      {:ok, thread} = Channel.open_thread(%{title: "the work", workspace_id: ws, scope: "machine"})
      {:ok, _} = Channel.assign_lead(thread.id, "hronir")
      _ = agent

      assert {:ok, receipt} = Orchestrator.dispatch({:post, "hronir", "ship it"}, ctx)
      assert receipt =~ "posted to ##{thread.id}"
      assert receipt =~ "woke @hronir"

      assert [%{body: "@hronir ship it", author: "andrew"}] =
               Repo.all(from(m in Server.Message, where: m.thread_id == ^thread.id))
    end

    test "post to a nonexistent coworker is a clean error", %{ctx: ctx} do
      assert {:error, msg} = Orchestrator.dispatch({:post, "ghost", "hi"}, ctx)
      assert msg =~ "no coworker @ghost"
    end

    test "an unmatched line passes through — posts to the machine (root) thread", %{ctx: ctx, workspace_id: ws} do
      {:ok, root} = Channel.open_thread(%{title: "general", workspace_id: ws, scope: "machine"})

      assert {:ok, receipt} = Orchestrator.dispatch({:chat, "just testing stuff"}, ctx)
      assert receipt =~ "posted to general"

      assert [%{body: "just testing stuff", author: "andrew"}] =
               Repo.all(from(m in Server.Message, where: m.thread_id == ^root.id))
    end

    test "passthrough posts to the ACTIVE workspace's root, not another workspace's", %{ctx: ctx, workspace_id: ws} do
      {:ok, mine} = Channel.open_thread(%{title: "general", workspace_id: ws, scope: "machine"})
      {:ok, other_ws} = Workspaces.register(%{name: "Elsewhere"})
      {:ok, theirs} = Channel.open_thread(%{title: "general", workspace_id: other_ws.id, scope: "machine"})

      assert {:ok, _} = Orchestrator.dispatch({:chat, "for my workspace only"}, ctx)

      assert [%{body: "for my workspace only"}] =
               Repo.all(from(m in Server.Message, where: m.thread_id == ^mine.id))

      assert [] == Repo.all(from(m in Server.Message, where: m.thread_id == ^theirs.id))
    end
  end

  describe "dispatch — consequential verbs confirm first" do
    test "open returns {:confirm, _} and does NOT create a thread yet", %{ctx: ctx} do
      before = Repo.aggregate(Server.Thread, :count)
      assert {:confirm, summary} = Orchestrator.dispatch({:open, "build", "a redis cache"}, ctx)
      assert summary =~ "a redis cache"
      assert Repo.aggregate(Server.Thread, :count) == before
    end

    test "confirm at a stage opens a WORKLINE at that stage — any-stage entry (Slice 4D)", %{ctx: ctx} do
      assert {:ok, receipt} = Orchestrator.confirm({:open, "build", "a redis cache"}, ctx)
      assert receipt =~ "opened #"
      t = Repo.one(from(t in Server.Thread, where: t.title == "a redis cache"))
      assert t.stage == "build"
      assert t.slug =~ "redis"
    end

    test "confirm with no stage opens an UNTRACKED plain thread (the explore verb)", %{ctx: ctx} do
      assert {:ok, receipt} = Orchestrator.confirm({:open, nil, "poke at the flake"}, ctx)
      assert receipt =~ "untracked"
      t = Repo.one(from(t in Server.Thread, where: t.title == "poke at the flake"))
      assert t.stage == nil
    end

    test "confirm approve on a missing thread, or one with no parked gate, errors cleanly", %{ctx: ctx} do
      assert {:error, msg} = Orchestrator.confirm({:approve, 999_999}, ctx)
      assert msg =~ "no thread"

      {:ok, plain} = Channel.open_thread(%{title: "not a workline", scope: "machine"})
      assert {:error, msg2} = Orchestrator.confirm({:approve, plain.id}, ctx)
      assert msg2 =~ "no parked gate"
    end
  end
end
