import Config

config :server, Server.Repo,
  database: Path.expand("../.dev/funes_test.db", __DIR__),
  pool_size: 1

# Bootstrap (seed + repair) is driven explicitly by its own suite; an app-boot
# run against the harness-owned repo would race the per-test TestDB.clean!.
config :server, bootstrap: false

# The consult mirror is off in tests: the pure maybe_mirror tests call it directly, and the
# round-trip test starts it explicitly. An always-on subscriber would double-mirror.
config :server, start_consult_mirror: false

# In test the harness manages the repo lifecycle (fresh, migrated DB per run),
# so the application does not start it. The DB is a repo-local scratch file,
# never the real one.
config :server, start_repo: false

# A fixed signing key for the stateless MCP tokens, so tests mint/resolve deterministically with
# no secret-file IO (Server.MCP.Secret reads this before touching disk).
config :server, token_secret: "test-only-token-secret-not-for-any-real-world-32b"
