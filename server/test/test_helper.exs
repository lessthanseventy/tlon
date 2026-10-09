alias Ecto.Adapters.Postgres

# A fresh, migrated test database per run. The application does not start the
# repo under :test (config/test.exs), so the harness owns its lifecycle.
config = Server.Repo.config()

# force_drop: a connection left over from an earlier run would otherwise make the drop fail
# quietly and the create below report :already_up.
:ok =
  case Postgres.storage_down(Keyword.put(config, :force_drop, true)) do
    {:error, :already_down} -> :ok
    other -> other
  end

:ok = Postgres.storage_up(config)

{:ok, _} = Server.Repo.start_link()
Ecto.Migrator.run(Server.Repo, :up, all: true)

ExUnit.start()
