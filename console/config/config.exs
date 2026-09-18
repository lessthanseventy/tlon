import Config

# Quiet raxol_terminal's internal debug/info chatter (e.g. Buffer.Writer "Writing char"):
# at runtime it would corrupt a live TUI, and in tests it drowns the output. aleph's own
# logs stay at :warning and above.
config :logger, level: :warning

# Oban, for the embedded (local-backend) cockpit — the server's own config.exs is not evaluated
# when the console is the root app, so the queues and the cron are re-declared here, the same as
# the service's: the drain, the Maintain sweeps, the staffing pass (one-brain B/3, E). runtime.exs
# flips `start_oban` on under the local backend.
config :server, Oban,
  engine: Oban.Engines.Basic,
  repo: Server.Repo,
  queues: [default: 5, maintain: 1, staff: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 3600},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Server.Jobs.Drain},
       {"*/30 * * * *", Server.Jobs.Maintain},
       {"* * * * *", Server.Jobs.Staff}
     ]}
  ]

# Postgres on the local socket (one-brain piece C); the database name comes from runtime.exs.
config :server, Server.Repo, socket_dir: "/run/postgresql", pool_size: 5

# The terminal backends are the server's own tmux ones (one-brain B/2): a wake is send-keys into
# the thread's window on the workspace's tmux server — the same window the cockpit embeds — and a
# crew role is a window beside it. In-node here; the same modules run in the always-up service.
config :server, :arbiter, Server.Arbiter.Tmux
config :server, :crew, Server.Crew.Tmux

# The engine-credit presence backend: the hand toggle (Server.Presence.clock_out/1 from the
# console) — when the scarce Claude window is spent, the switchboard stops poking Claude
# sessions. A real rate-limit reader is a later local backend swapped in the same seam.
config :server, :engine_presence, Server.Presence.Engine.Manual

# aleph boots funes as a live dep (§6), but a dependency's own config/*.exs is NOT evaluated
# when aleph is the root app — so aleph re-declares what funes' config.exs normally provides:
# the ecto repo list and the §4 write contract (WAL + busy timeout + foreign keys). The DB
# *path* is env/runtime-resolved (config/runtime.exs); it must not be hardcoded here.
config :server, ecto_repos: [Server.Repo]

# A DISTINCT port from the always-up service's 4040, so the hub and the headless service
# coexist on one box (topology A: they are two funes workspaces on two DBs). Both aleph's Bandit
# and its in-process `Server.MCP.Spawn` env read `:mcp_port`, so a spawned harness is pointed
# at exactly the endpoint aleph serves. Override with TLON_MCP_PORT in aleph's runtime if 4041
# is taken.
config :server, mcp_port: 4041

# The profile registry lives in the server now (one-brain B/2); on a cockpit that is a CLIENT of
# the service it reads workspace policy through the facade (erpc), and a coworker it launches
# itself runs pi through mise, the way this interactive shell does.
config :server, profiles_workspaces: Console.Server.Workspaces
config :server, spawn_launcher_pi: "mise exec -- pi"
config :server, start_mcp: true

# aleph is the dogfood HUB (tlön topology A): it runs the full funes workspace in one interactive node,
# so the switchboard's wake loop and the MCP channel start here, and sessions are embedded ghostty
# terminals aleph owns (not tmux). The presence gate the wake needs (warmth AND engine-credit)
# exists; the live poke is Server.Arbiter.Tmux's send-keys.
config :server, start_switchboard: true

import_config "#{config_env()}.exs"
