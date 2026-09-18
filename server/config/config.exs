import Config

# Postgres is the store (one-brain piece C, 2026-09-18): the §4 write contract — readers never
# blocked by a writer, real foreign keys, a bounded wait on a lock — is the engine's own.
# Connection details are per-env (dev/test below, runtime.exs for the release).
config :server, Server.Repo, socket_dir: "/run/postgresql", pool_size: 5
config :server, ecto_repos: [Server.Repo]

import_config "#{config_env()}.exs"
