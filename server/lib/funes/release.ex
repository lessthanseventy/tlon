defmodule Server.Release do
  @moduledoc """
  Release-time tasks — the operations a `mix release` needs but `mix` isn't there
  to perform. The always-up service (a self-contained release, no toolchain on
  PATH) boots by first running `bin/server eval 'Server.Release.migrate()'`, so an
  empty or behind schema is brought fully up before the channel serves. SQLite is
  the truth; nothing ships that cannot be repaired at 2am, and migration is the
  first repair — so it lives here, in the app, not in a shell step that could drift.
  """
  @app :server

  @doc """
  Apply every pending migration for each configured repo, up to the latest.
  Runs against the repo's own priv migrations (bundled into the release). Returns
  `:ok`. Idempotent — an up-to-date schema runs nothing.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Roll `repo` back to migration `version` — the deliberate 2am reverse gear. Named
  repo + explicit version, never "roll back one blindly": a repair is a decision.
  """
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  # Load (not start) the app so its config — including :ecto_repos and the repo's
  # database path from runtime.exs — is available without booting the supervision
  # tree. `with_repo` starts just the repo it needs and stops it after.
  defp load_app, do: Application.load(@app)
end
