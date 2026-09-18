import Config

# The store: Postgres on the local socket. TLON_DATABASE_URL names another (a remote, a
# password); otherwise TLON_DATABASE (default `tlon`) over peer auth at /run/postgresql. Test
# manages its own database (config/test.exs), so skip it here.
if config_env() != :test do
  case System.get_env("TLON_DATABASE_URL") do
    nil -> config :server, Server.Repo, database: System.get_env("TLON_DATABASE") || "tlon", socket_dir: "/run/postgresql"
    url -> config :server, Server.Repo, url: url
  end
end

# Where workline artifact checks run git (`Server.Workline.Artifacts.Git`) — the workspace's
# checkout. Unset → cwd, right for dev shells, WRONG for a release whose cwd is elsewhere
# (the checker then reports the environment fault, not a fake "not committed").
if root = System.get_env("TLON_WORKLINE_ROOT") do
  config :server, workline_root: root
end

# The Maintain monitor is opt-in the same way: control-band sweeps that
# nag stale gates and flag stalled worklines as gated machine-born intents.
config :server, maintain: System.get_env("TLON_MAINTAIN") in ~w(1 true yes)

# The post-response memory pass is opt-in: presence_idle → cheap
# extractor → banked facts. Off by default so a dev shell never shells a model unasked.
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

# The terminal backends when this node is the always-up server and the cockpit is a client
# (docs/plans/2026-09-08-one-brain-client-server-plan.md phase 3): the connected cockpit's
# Console.Arbiter / Console.Crew over distribution, `{:error, :no_cockpit}` when none is — the
# same degrade as no backend. Only the release evaluates this file; the embedded console (Local
# backend) is the root app there and sets both to its own modules in its config. Guarded out
# of :test (the suite uses Server.Arbiter.Test).
if config_env() != :test do
  config :server, arbiter: Server.Arbiter.Remote, crew: Server.Crew.Remote
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
