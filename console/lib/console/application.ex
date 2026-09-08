defmodule Console.Application do
  @moduledoc """
  console's OTP entrypoint. Supervises the session layer — a `DynamicSupervisor` for the embedded
  session terminals (`Console.Terminal`) and the `Console.Sessions` registry over it — so a session
  outlives a render and a crash never takes the cockpit down. The cockpit itself grabs the TTY and
  is NOT supervised here (it runs only under `mix console.run`).
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {DynamicSupervisor, name: Console.TerminalSup, strategy: :one_for_one},
        Console.Sessions
      ] ++ maybe_link() ++ maybe_workspaces()

    Supervisor.start_link(children, strategy: :one_for_one, name: Console.Supervisor)
  end

  # Event-driven cache of the server's workspaces so the per-render picker/survey never hit the DB. Gated
  # off under test (config/test.exs: `start_workspaces: false`): the app-global would subscribe to the
  # server workspaces Bus and cache workspaces registered by async DB tests, polluting Space.all/0 for the
  # pure-render tests. With it unstarted, fetch_workspaces/0 degrades to [] → the deterministic Tlön
  # fallback the render tests rely on.
  # the node link to the always-up server, only under the Remote backend (Local = the server is
  # in this node: tests, server:dev); Workspaces comes after it so its first cache fill can land
  defp maybe_link do
    if Console.Backend.impl() == Console.Backend.Remote,
      do: [{Registry, keys: :duplicate, name: Console.Backend.Link.Registry}, Console.Backend.Link],
      else: []
  end

  defp maybe_workspaces do
    if Application.get_env(:console, :start_workspaces, true), do: [Console.Workspaces], else: []
  end
end
