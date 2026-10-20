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

# gateway.sh refuses an ollama-cloud model without a key; the suite's stand-in CLIs never reach
# ollama.com, so a box without one (CI) gets a placeholder
if System.get_env("OLLAMA_API_KEY") in [nil, ""], do: System.put_env("OLLAMA_API_KEY", "test-placeholder")

# Every @tag :tmp_dir test leaves a git repo under tmp/, and each repo under a seat's write roots
# costs bwrap mounts: a few suite runs took every seat past bwrap's 9000 arguments (#496). Gone
# before the run (a killed run's) and after it.
File.rm_rf!(Path.expand("tmp"))
ExUnit.after_suite(fn _ -> File.rm_rf(Path.expand("tmp")) end)

ExUnit.start()
