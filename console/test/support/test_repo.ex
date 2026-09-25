defmodule Console.TestRepo do
  @moduledoc """
  The DB harness for the few console suites that drive the real `Server` contexts. The console
  test env keeps `Server.Repo` DOWN (config/test.exs `start_repo: false`) so the pure render
  suites never touch a database; a suite that needs one calls `boot!/1` from `setup_all`
  (→ `async: false`) and gets a fresh, migrated, throwaway SQLite file torn down on exit.

  Migration modules are compiled ONCE per VM and cached: `Ecto.Migrator` never purges what it
  compiles, so a second `run/3` over the files would redefine every module — a warning, and the
  gate runs `--warnings-as-errors`.

  Owning the Repo lifecycle means touching `Server.Repo`, which `Server` deliberately does not
  export — so this one test-support module opts out of the outgoing-reference check.
  """
  use Boundary, top_level?: true, check: [out: false]

  alias Ecto.Adapters.Postgres
  alias Server.Repo

  # Children before parents, so `delete_all` never trips a foreign key. Mirrors
  # `Server.TestDB.@ordered`, which is test-support of the server app and not compiled into ours.
  @ordered [
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
    # channel.workspace_id → workspace (UX slice 1b)
    Server.ChannelRow,
    Server.Workspace
  ]

  @doc """
  Boot a fresh, migrated scratch database for the calling suite. Call from `setup_all`; the Repo is
  stopped and the database dropped on exit. `name` labels it.
  """
  @spec boot!(String.t()) :: :ok
  def boot!(name) do
    db = "tlon_console_#{name}_#{System.unique_integer([:positive])}"

    Application.put_env(
      :server,
      Repo,
      Keyword.merge(Application.get_env(:server, Repo, []), database: db, socket_dir: "/run/postgresql", pool_size: 5)
    )

    config = Repo.config()
    _ = Postgres.storage_down(config)
    :ok = Postgres.storage_up(config)
    {:ok, repo} = Repo.start_link()
    # Unlinked: setup_all's process exits before on_exit runs, and a linked Repo would be shutting down
    # under that exit while on_exit stops it — a race that fails the whole suite after its tests ran.
    Process.unlink(repo)
    Ecto.Migrator.run(Repo, migrations(), :up, all: true, log: false)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.whereis(Repo), do: Repo.stop()
      _ = Postgres.storage_down(config)
    end)

    :ok
  end

  @doc "Delete every domain row, children before parents."
  @spec clean!() :: :ok
  def clean! do
    Enum.each(@ordered, &Repo.delete_all/1)
  end

  defp migrations do
    key = {__MODULE__, :migrations}

    case :persistent_term.get(key, nil) do
      nil ->
        loaded = Enum.map(migration_files(), &load_migration/1)
        :persistent_term.put(key, loaded)
        loaded

      loaded ->
        loaded
    end
  end

  defp migration_files do
    Repo |> Ecto.Migrator.migrations_path() |> Path.join("*.exs") |> Path.wildcard() |> Enum.sort()
  end

  defp load_migration(file) do
    [version | _] = file |> Path.basename() |> String.split("_", parts: 2)
    [{mod, _bin} | _] = Code.compile_file(file)
    {String.to_integer(version), mod}
  end
end
