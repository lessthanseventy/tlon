defmodule Console.WorkspacesDownTest do
  @moduledoc """
  The funes-down guard (Task B1), isolated from the DB suite below: aleph's test env
  keeps funes' Repo DOWN (config/test.exs `start_repo: false`), so `Server.Workspaces.all/0`
  raises here. `Console.Workspaces` must swallow that at init and serve `[]` — proving a funes
  hiccup can never crash aleph boot. No Repo is started, so nothing to tear down.
  """
  use ExUnit.Case, async: false

  test "funes down at init is swallowed → [] (aleph boot never crashes)" do
    name = :"workspaces_down_#{System.unique_integer([:positive])}"
    {:ok, pid} = Console.Workspaces.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Console.Workspaces.all(pid) == []
  end
end

defmodule Console.WorkspacesTest do
  @moduledoc """
  The `Console.Workspaces` cache (workspaces/orbis Slice 1, Task B1): an event-driven read of
  funes' `workspace` table, so the per-render hot paths (`Space.all/0`, the survey) hit a
  cached list instead of the DB every frame. Drives the real `Server.Workspaces`/`Server.Bus`
  against a `Console.TestRepo` scratch db → `async: false`.
  """
  use ExUnit.Case, async: false

  alias Server.Repo
  alias Server.Workspace
  alias Server.Workspaces

  setup_all do
    Console.TestRepo.boot!("workspaces")

    :ok
  end

  setup do
    # A clean workspace table per test — this is the only suite writing rows.
    Repo.delete_all(Server.ChannelRow)
    Repo.delete_all(Workspace)
    :ok
  end

  # An isolated cache instance (the app already supervises one under the module name).
  defp start_workspaces do
    name = :"workspaces_#{System.unique_integer([:positive])}"
    {:ok, pid} = Console.Workspaces.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  test "all/0 returns the workspaces present at boot, aleph-shaped" do
    {:ok, registered} =
      Workspaces.register(%{
        name: "Tlön",
        type: "code",
        scope: "machine",
        paths: ["modules/*"],
        roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
      })

    pid = start_workspaces()

    assert [workspace] = Console.Workspaces.all(pid)

    assert workspace == %{
             id: registered.id,
             name: "Tlön",
             type: "code",
             scope: "machine",
             paths: ["modules/*"],
             roster: [%{"archetype" => "surveyor", "name" => "tertius"}]
           }
  end

  test "cached workspaces carry the funes id" do
    {:ok, w} = Workspaces.register(%{name: "Test", type: "code"})

    pid = start_workspaces()

    assert [%{id: id, name: "Test"}] = Console.Workspaces.all(pid)
    assert id == w.id
  end

  test "a :workspace_registered Bus event refreshes the cache" do
    pid = start_workspaces()
    assert Console.Workspaces.all(pid) == []

    # register/1 announces on the workspaces topic; the cache is subscribed and reloads.
    # FIFO mailbox: the broadcast lands before the following all/0 call, so no sleep.
    {:ok, _} = Workspaces.register(%{name: "Orbis", type: "code"})

    assert [%{name: "Orbis"}] = Console.Workspaces.all(pid)
  end

  test "all/0 serves the cache, not a live DB read: a direct insert stays invisible until its event lands" do
    pid = start_workspaces()
    assert Console.Workspaces.all(pid) == []

    # Insert straight through the Repo, BYPASSING Workspaces.register/1 so NO :workspace_registered
    # is announced. A naive per-call live read would see this row; a genuine cache does not.
    {:ok, ghost} = Repo.insert(Workspace.register_changeset(%{name: "Ghost", type: "code"}))

    # Still stale — the row is in the DB but the cache never re-read it on the call.
    # This assertion is what distinguishes a cache from a live read: a live read fails here.
    assert Console.Workspaces.all(pid) == []

    # Deliver the event the real write pipe (Workspaces.register/1) would have broadcast. FIFO
    # mailbox: this handle_info runs before the following all/0 call, so no sleep is needed.
    # The cache refreshes ONLY now → the EVENT, not the call, drives the reload.
    send(pid, {:workspace_registered, ghost})
    assert [%{name: "Ghost"}] = Console.Workspaces.all(pid)
  end

  test "no workspaces → []" do
    pid = start_workspaces()
    assert Console.Workspaces.all(pid) == []
  end
end
