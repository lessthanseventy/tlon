alias Ecto.Adapters.Postgres

# A fresh, migrated test database per run. The application does not start the
# repo under :test (config/test.exs), so the harness owns its lifecycle.
config = Server.Repo.config()

_ = Postgres.storage_down(config)
:ok = Postgres.storage_up(config)

{:ok, _} = Server.Repo.start_link()
Ecto.Migrator.run(Server.Repo, :up, all: true)

ExUnit.start()
