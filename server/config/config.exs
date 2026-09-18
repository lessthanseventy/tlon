import Config

# Phoenix + LiveView (one-brain piece D) — the same Bandit family as the MCP channel, a second
# loopback listener; runtime.exs sets the port and the start flag, and derives the secrets.
config :phoenix, :json_library, JSON

# Oban (one-brain piece E): the queue is a Postgres table; cron for the recurring work.
config :server, Oban,
  engine: Oban.Engines.Basic,
  repo: Server.Repo,
  queues: [default: 5, maintain: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 3600},
    {Oban.Plugins.Cron,
     crontab: [
       # the switchboard's durability path, once a minute — a message posted while no recipient
       # was live is delivered the moment one appears, not only on the next boot
       {"* * * * *", Server.Jobs.Drain},
       # the control-band sweeps (stale gates nagged, stalled worklines flagged), every half hour
       {"*/30 * * * *", Server.Jobs.Maintain}
     ]}
  ]

# Postgres is the store (one-brain piece C, 2026-09-18): the §4 write contract — readers never
# blocked by a writer, real foreign keys, a bounded wait on a lock — is the engine's own.
# Connection details are per-env (dev/test below, runtime.exs for the release).
config :server, Server.Repo, socket_dir: "/run/postgresql", pool_size: 5

config :server, Server.Web.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "127.0.0.1"],
  render_errors: [formats: [html: Server.Web.ErrorHTML], layout: false],
  pubsub_server: Server.PubSub,
  live_view: [signing_salt: "tlon-live-view"],
  # the listener is loopback, so the origin check guards nothing — but a tab at localhost or the
  # box's tailscale name reconnecting every minute logged "Could not check origin" (2026-09-18)
  check_origin: ["//127.0.0.1", "//localhost", "//ivysaur", "//*.ts.net"],
  http: [ip: {127, 0, 0, 1}, port: 4042],
  server: false

config :server, ecto_repos: [Server.Repo]

import_config "#{config_env()}.exs"
