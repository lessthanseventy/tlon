alias Ecto.Adapters.SQLite3

# A fresh, migrated test database per run. The application does not start the
# repo under :test (config/test.exs), so the harness owns its lifecycle.
config = Server.Repo.config()
File.mkdir_p!(Path.dirname(config[:database]))

_ = SQLite3.storage_down(config)
:ok = SQLite3.storage_up(config)

{:ok, _} = Server.Repo.start_link()
Ecto.Migrator.run(Server.Repo, :up, all: true)

ExUnit.start()
