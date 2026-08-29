defmodule Mix.Tasks.Console.Run do
  @shortdoc "Launch the aleph cockpit in this terminal (run in ghostty)"
  @moduledoc """
  Boot funes (Repo + Bus) and launch the live cockpit — the space picker, the reactive board,
  the tmux center, chat — over the funes workspace at `TLON_DB`. Runs until you quit (`q`).

  Run in a REAL terminal: `mise run aleph:run` (headless it boots funes, finds no TTY, and exits
  clean). Set up the DB first with `mise run aleph:setup`, and `mise run aleph:seed` for sample data.
  """
  use Mix.Task
  use Boundary, classify_to: Console

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    # Start aleph and its deps — funes' OTP app (PubSub always, Repo from aleph's config) comes up
    # as a dependency. A DB misconfig surfaces here rather than deep in the first read.
    case Application.ensure_all_started(:console) do
      {:ok, _apps} ->
        launch_or_explain()

      {:error, reason} ->
        Mix.shell().error(
          "aleph could not boot funes: #{inspect(reason)}\n" <>
            "Did you run `mise run aleph:setup` to create + migrate the database?"
        )
    end
  end

  # The DB opens fine but may be BEHIND — a slice that landed a migration leaves the
  # repo-local scratch db a `mise run aleph:setup` short, and `home:switch` migrates only
  # the XDG service db, not this one. The cockpit's first read would then raise a raw
  # `%Exqlite.Error{}` ("no such table: todo") deep in render. So ask the arbiter whose
  # output names the gap — `Server.Doctor.pending/0` — and turn that crash into the fix.
  defp launch_or_explain do
    case Server.Doctor.pending() do
      [] ->
        Console.Cockpit.run()

      pending ->
        names = Enum.map_join(pending, "\n  ", fn {version, name} -> "#{version}_#{name}" end)

        Mix.shell().error(
          "aleph's database is #{length(pending)} migration(s) behind — run `mise run aleph:setup` first.\n" <>
            "Pending:\n  " <> names
        )
    end
  end
end
