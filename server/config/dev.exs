import Config

# A dev shell's own database on the local Postgres (peer auth over the socket).
config :server, Server.Repo, database: "tlon_dev", pool_size: 5
