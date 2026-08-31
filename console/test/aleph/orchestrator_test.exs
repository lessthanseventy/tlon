defmodule Console.OrchestratorTest do
  @moduledoc """
  The tertius command line's dispatch (Slice 1). funes runs in-process in the console, but the
  console test env keeps funes' Repo DOWN (config/test.exs `start_repo: false`), so this suite
  boots the Repo itself — mirroring `Console.WorkspacesTest` and funes' own test_helper. Touches
  the DB → `async: false`.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQLite3
  alias Console.Orchestrator
  alias Server.Channel
  alias Server.Repo
  alias Server.Staff
  alias Server.Tickets
  alias Server.Workspaces

  setup_all do
    db = Path.join(System.tmp_dir!(), "aleph_orchestrator_test_#{System.unique_integer([:positive])}.db")
    Application.put_env(:server, Repo, Keyword.merge(Application.get_env(:server, Repo, []), database: db, pool_size: 1))

    config = Repo.config()
    _ = SQLite3.storage_down(config)
    :ok = SQLite3.storage_up(config)
    {:ok, _repo} = Repo.start_link()
    Ecto.Migrator.run(Repo, :up, all: true)

    on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = SQLite3.storage_down(config)
    end)

    :ok
  end

  setup do
    # FK-safe clean (children before parents) — mirrors Server.TestDB.@ordered, which isn't
    # compiled into the console app.
    for schema <- [
          Server.Ticket,
          Server.Note,
          Server.Fact,
          Server.Event,
          Server.Issue,
          Server.Todo,
          Server.Question,
          Server.Habit,
          Server.Message,
          Server.Session,
          Server.Thread,
          Server.Agent,
          Server.Project,
          Server.Workspace
        ] do
      Repo.delete_all(schema)
    end

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
      assert [%{body: "leads are managers", scope: "workspace", scope_id: ^ws}] = Server.Notes.for_scope("workspace", ws)
    end

    test "post to a coworker leading a thread posts + names the wake", %{ctx: ctx, workspace_id: ws} do
      {:ok, agent} = Staff.register_agent(%{name: "hronir-machine", mandate: "build", engine: "fresh"})
      {:ok, thread} = Channel.open_thread(%{title: "the work", workspace_id: ws, scope: "machine"})
      {:ok, _} = Channel.assign_lead(thread.id, "hronir-machine")
      _ = agent

      assert {:ok, receipt} = Orchestrator.dispatch({:post, "hronir-machine", "ship it"}, ctx)
      assert receipt =~ "posted to ##{thread.id}"
      assert receipt =~ "woke @hronir-machine"
      assert [%{body: "@hronir-machine ship it", author: "andrew"}] =
               Repo.all(from m in Server.Message, where: m.thread_id == ^thread.id)
    end

    test "post to a nonexistent coworker is a clean error", %{ctx: ctx} do
      assert {:error, msg} = Orchestrator.dispatch({:post, "ghost", "hi"}, ctx)
      assert msg =~ "no coworker @ghost"
    end

    test "an unmatched line passes through — posts to the machine (root) thread", %{ctx: ctx, workspace_id: ws} do
      {:ok, root} = Channel.open_thread(%{title: "general", workspace_id: ws, scope: "machine"})

      assert {:ok, receipt} = Orchestrator.dispatch({:chat, "just testing stuff"}, ctx)
      assert receipt =~ "posted to general"
      assert [%{body: "just testing stuff", author: "andrew"}] = Repo.all(from m in Server.Message, where: m.thread_id == ^root.id)
    end
  end

  describe "dispatch — consequential verbs confirm first" do
    test "open returns {:confirm, _} and does NOT create a thread yet", %{ctx: ctx} do
      before = Repo.aggregate(Server.Thread, :count)
      assert {:confirm, summary} = Orchestrator.dispatch({:open, "build", "a redis cache"}, ctx)
      assert summary =~ "a redis cache"
      assert Repo.aggregate(Server.Thread, :count) == before
    end

    test "confirm actually opens the thread", %{ctx: ctx} do
      assert {:ok, receipt} = Orchestrator.confirm({:open, "build", "a redis cache"}, ctx)
      assert receipt =~ "opened #"
      assert Repo.exists?(from(t in Server.Thread, where: t.title == "a redis cache"))
    end
  end
end
