defmodule Console.Workspaces do
  @moduledoc """
  An event-driven cache of the server's workspaces (workspaces/orbis Slice 1, Task B1).

  `Space.all/0` and the Orbis survey are per-render hot paths — reading
  `Server.Workspaces.all/0` there would be a server DB hit every frame, the same
  per-frame-gather regression the survey already caught. So this GenServer loads the
  workspace list once, subscribes to the server workspaces Bus topic, and reloads only when a
  workspace is registered/edited/removed. `all/0` then serves the cached list — no DB per
  render. server runs in-process in console (the cockpit already reads `Server.Board`/
  `Server.Channel` directly), so `Server.Workspaces`/`Server.Bus` work like any local call.

  `all/0` is a `GenServer.call`, not a `:persistent_term` read: the caller is the single
  cockpit render process, so there is no call contention, and the win we needed was
  killing the *DB* hit (the cache does that) — the message round-trip is negligible and
  keeps the state per-instance (testable) rather than global.

  Server-down at boot or an empty table both yield `[]`; callers (B2/B3) decide the
  hardcoded-Tlön fallback. The load is guarded so a server hiccup can never crash console
  boot — a failed reload keeps the previous cache.
  """
  use GenServer

  alias Server.Bus

  require Logger

  @workspace_events [:workspace_registered, :workspace_edited, :workspace_removed]
  # The console-shaped subset lifted off each `Server.Workspace` — dropping `knobs`/`created_at`.
  # Taken by key (not a struct match) so console needn't reference the server's unexported struct.
  @fields [:id, :name, :type, :paths, :roster, :scope]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  The cached workspaces as console-shaped `%{id, name, type, paths, roster, scope}` maps.

  Cache down (boot race, or the test env where this GenServer never runs) degrades to
  the caller-process fixture `Process.get(:aleph_workspaces, [])` — the seam tests push a
  workspace list through now that the hardcoded fallback Workspace is gone (reshape slice A).
  Process-scoped so async suites can't race each other's fixtures.
  """
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all)
  catch
    :exit, _ -> Process.get(:aleph_workspaces, [])
  end

  @impl true
  def init(_opts) do
    subscribe()
    {:ok, load([])}
  end

  # Guarded like `load/1`: if the server's PubSub is down at boot, degrade to an unsubscribed
  # empty cache instead of crash-looping the supervisor. Happy path is a plain subscribe.
  defp subscribe do
    Bus.subscribe_workspaces()
  rescue
    e -> Logger.warning("Console.Workspaces: workspaces subscribe failed (#{inspect(e)}); cache won't refresh")
  catch
    :exit, reason ->
      Logger.warning("Console.Workspaces: workspaces subscribe exited (#{inspect(reason)}); cache won't refresh")
  end

  @impl true
  def handle_call(:all, _from, workspaces), do: {:reply, workspaces, workspaces}

  @impl true
  def handle_info({tag, _workspace}, workspaces) when tag in @workspace_events do
    {:noreply, load(workspaces)}
  end

  def handle_info(_msg, workspaces), do: {:noreply, workspaces}

  # Load + shape the workspace list; on any server error keep `fallback` (init: `[]`; a
  # reload: the prior cache) so a DB blip never takes the cockpit down.
  defp load(fallback) do
    Enum.map(Console.Server.Workspaces.all(), &shape/1)
  rescue
    _ -> fallback
  catch
    :exit, _ -> fallback
  end

  defp shape(workspace), do: Map.take(workspace, @fields)
end
