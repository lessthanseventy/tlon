import Config

# The store: Postgres on the local socket. TLON_DATABASE_URL names another (a remote, a
# password); otherwise TLON_DATABASE (default `tlon`) over peer auth at /run/postgresql. Test
# manages its own database (config/test.exs), so skip it here.
# In :prod the default is the service's `tlon`; in :dev the default stays dev.exs's `tlon_dev`
# (2026-09-18: a dev-env `server:check` wrote eval threads into the LIVE store when this block
# defaulted every env to `tlon`) — TLON_DATABASE / TLON_DATABASE_URL override either.
if config_env() != :test do
  case {System.get_env("TLON_DATABASE_URL"), System.get_env("TLON_DATABASE"), config_env()} do
    {url, _, _} when is_binary(url) -> config :server, Server.Repo, url: url
    {nil, db, _} when is_binary(db) -> config :server, Server.Repo, database: db, socket_dir: "/run/postgresql"
    {nil, nil, :prod} -> config :server, Server.Repo, database: "tlon", socket_dir: "/run/postgresql"
    _ -> :ok
  end
end

# Where workline artifact checks run git (`Server.Workline.Artifacts.Git`) — the workspace's
# checkout. Unset → cwd, right for dev shells, WRONG for a release whose cwd is elsewhere
# (the checker then reports the environment fault, not a fake "not committed").
if root = System.get_env("TLON_WORKLINE_ROOT") do
  config :server, workline_root: root
end

# The post-response memory pass is opt-in: presence_idle → a queued pass → cheap extractor →
# banked facts. Off by default so a dev shell never shells a model unasked. (The Maintain
# sweeps need no flag: they run on Oban's cron wherever Oban runs, E/2.)
config :server, memory_pass: System.get_env("TLON_MEMORY_PASS") in ~w(1 true yes)

# The operator's handle — who the human IS on this machine's channel. Local
# configuration, never identity in the design (§8); the same default the console uses.
# `Dossier.bank_stated_fact` trusts only this author for `stated` provenance.
config :server, operator: System.get_env("TLON_OPERATOR") || "andrew"

# The sovereign channel is opt-in (pi doc §2a): a node that serves agents flips it on.
# `mise run server:serve` sets TLON_START_MCP=1 so a hand-spawned pi pane has something to
# register with. Guarded out of :test — the suite owns its own MCP lifecycle on its own
# port, and this guard means a stray TLON_START_MCP=1 in a dev shell can't bind Bandit
# during `mix test`. The port is loopback-only (Server.Application); TLON_MCP_PORT lets a
# second node avoid a clash.
if config_env() != :test do
  config :server,
    start_mcp: System.get_env("TLON_START_MCP") in ~w(1 true yes),
    mcp_port: String.to_integer(System.get_env("TLON_MCP_PORT") || "4040")
end

# The switchboard runner (deliver + wake) is opt-in per node the same way — the service sets
# TLON_START_SWITCHBOARD=1 for the durable bookkeeping even with no arbiter to poke. Guarded
# out of :test: the suite starts the runner itself where a test needs it.
if config_env() != :test do
  config :server, start_switchboard: System.get_env("TLON_START_SWITCHBOARD") in ~w(1 true yes)
end

# The attention poller (master plan piece A): reads every coworker pane every few seconds and
# turns a permission dialog into a `prompt` message on the thread. Service-only, like the rest.
if config_env() != :test do
  config :server, start_attention: System.get_env("TLON_START_ATTENTION") in ~w(1 true yes)
end

# The terminal backends: the server's own tmux ones (one-brain piece B, slices 1–2). A wake is
# send-keys into the thread's window on the workspace's tmux server, a spawn a new window there,
# a crew role a window beside the lead — with or without a cockpit connected. Guarded out of
# :test (the suite uses Server.Arbiter.Test / Server.Crew.Test).
if config_env() != :test do
  config :server, arbiter: Server.Arbiter.Tmux, crew: Server.Crew.Tmux
end

# The web UI (one-brain piece D): opt-in like MCP — TLON_START_WEB=1, TLON_WEB_PORT (4042),
# loopback only; reachable remotely over tailscale alone. Its secret is derived from the same
# world secret the MCP tokens use, so a fresh box needs nothing more.
if config_env() != :test do
  config :server, Server.Web.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("TLON_WEB_PORT") || "4042")],
    secret_key_base:
      Base.encode64(:crypto.hash(:sha512, "tlon-web:" <> (System.get_env("TLON_WEB_SECRET") || Server.MCP.Secret.get()))),
    server: System.get_env("TLON_START_WEB") in ~w(1 true yes)

  # Oban runs where the switchboard runs (the service); a scratch node without it stays quiet.
  config :server, start_oban: System.get_env("TLON_START_OBAN") in ~w(1 true yes)
  config :server, start_web: System.get_env("TLON_START_WEB") in ~w(1 true yes)
end
