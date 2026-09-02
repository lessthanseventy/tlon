import Config

# The database path is resolved from the environment only — no distro-isms, no
# hardcoded home. TLON_DB overrides; otherwise the XDG data dir, defaulting to
# ~/.local/share. Test manages its own path (config/test.exs), so skip it here.
if config_env() != :test do
  data_home =
    System.get_env("XDG_DATA_HOME") ||
      Path.join(System.get_env("HOME") || ".", ".local/share")

  database = System.get_env("TLON_DB") || Path.join([data_home, "tlon", "wb.db"])
  File.mkdir_p!(Path.dirname(database))

  config :server, Server.Repo, database: database
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
