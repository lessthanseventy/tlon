import Config

# The read side wants a small pool; the cockpit is a single reader. The DB path is resolved
# at runtime (config/runtime.exs) so it can follow TLON_DB and land on the same file funes'
# own mise tasks use.
config :server, Server.Repo, pool_size: 5
