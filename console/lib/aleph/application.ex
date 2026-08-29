defmodule Console.Application do
  @moduledoc """
  aleph's OTP entrypoint. Supervises the session layer — a `DynamicSupervisor` for the embedded
  session terminals (`Console.Terminal`) and the `Console.Sessions` registry over it — so a session
  outlives a render and a crash never takes the cockpit down. The cockpit itself grabs the TTY and
  is NOT supervised here (it runs only under `mix aleph.run`).
  """
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {DynamicSupervisor, name: Console.TerminalSup, strategy: :one_for_one},
        Console.Sessions
      ] ++ maybe_workspaces()

    Supervisor.start_link(children, strategy: :one_for_one, name: Console.Supervisor)
  end

  # Event-driven cache of funes' workspaces so the per-render picker/survey never hit the DB. Gated
  # off under test (config/test.exs: `start_workspaces: false`): the app-global would subscribe to the
  # funes workspaces Bus and cache workspaces registered by async DB tests, polluting Space.all/0 for the
  # pure-render tests. With it unstarted, fetch_workspaces/0 degrades to [] → the deterministic Tlön
  # fallback the render tests rely on.
  defp maybe_workspaces do
    if Application.get_env(:console, :start_workspaces, true), do: [Console.Workspaces], else: []
  end
end
