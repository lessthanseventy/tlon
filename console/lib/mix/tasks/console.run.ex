defmodule Mix.Tasks.Console.Run do
  @shortdoc "Launch the console cockpit in this terminal (run in ghostty)"
  @moduledoc """
  Boot server (Repo + Bus) and launch the live cockpit — the space picker, the reactive board,
  the tmux center, chat — over the server workspace at `TLON_DB`. Runs until you quit (`q`).

  Run in a REAL terminal: `mise run console:run` (headless it boots server, finds no TTY, and exits
  clean). Set up the DB first with `mise run console:setup`, and `mise run console:seed` for sample data.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  alias Console.Backend.Remote

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # Start console and its deps — the server's OTP app (PubSub always, Repo from console's config) comes up
    # as a dependency. A DB misconfig surfaces here rather than deep in the first read.
    case Application.ensure_all_started(:console) do
      {:ok, _apps} ->
        launch_or_explain()

      {:error, reason} ->
        Mix.shell().error(
          "console could not boot server: #{inspect(reason)}\n" <>
            "Did you run `mise run console:setup` to create + migrate the database?"
        )
    end
  end

  # The DB opens fine but may be BEHIND — a slice that landed a migration leaves the
  # repo-local scratch db a `mise run console:setup` short, and `home:switch` migrates only
  # the XDG service db, not this one. The cockpit's first read would then raise a raw
  # `%Exqlite.Error{}` ("no such table: todo") deep in render. So ask the arbiter whose
  # output names the gap — `Server.Doctor.pending/0` — and turn that crash into the fix.
  defp launch_or_explain do
    # under the remote backend the first read is over the wire: give the node link a moment,
    # and say so if the service is not there (docs/plans/2026-09-08-one-brain-client-server-plan.md)
    case await_server() do
      :ok ->
        check_migrations_and_launch()

      {:error, :server_down} ->
        Mix.shell().error(
          "console cannot reach the tlon service node #{Remote.node_name()} — " <>
            "is it running (`systemctl --user status tlon`)? For an embedded server on the scratch db: `mise run console:run:local`."
        )
    end
  end

  defp await_server do
    if Console.Backend.impl() == Remote, do: Console.Backend.Link.await(5_000), else: :ok
  end

  defp check_migrations_and_launch do
    case Console.Server.Doctor.pending() do
      [] ->
        Console.Cockpit.run()

      pending ->
        names = Enum.map_join(pending, "\n  ", fn {version, name} -> "#{version}_#{name}" end)

        Mix.shell().error(
          "the server's database is #{length(pending)} migration(s) behind — `mise run server:restart` (service) or `mise run console:setup` (scratch db) first.\n" <>
            "Pending:\n  " <> names
        )
    end
  end
end
