import Config

# Oban never runs jobs on its own in test — a test performs them.
config :server, Oban, testing: :manual

# The suite's own database on the local Postgres, created fresh per run by test_helper.
config :server, Server.Repo, database: "tlon_test", pool_size: 5

# The web endpoint is started by the suite that tests it (no listener); fixed secrets.
config :server, Server.Web.Endpoint,
  secret_key_base: String.duplicate("t", 64),
  server: false

# Bootstrap (seed + repair) is driven explicitly by its own suite; an app-boot
# run against the harness-owned repo would race the per-test TestDB.clean!.
config :server, bootstrap: false

# The suite is headless: recall's query embedding points at a port nothing listens on, so it
# degrades to keyword relevance instantly instead of reaching a real ollama.
config :server, embedding: [endpoint: "http://127.0.0.1:1/api/embed", timeout: 200]

# Point the operator settings file away from the real ~/.config so the box's own overrides can
# never leak into test assertions; tests that want one pass an explicit path.
config :server, operator_config_path: "/nonexistent/tlon-test-config.json"

# The consult mirror is off in tests: the pure maybe_mirror tests call it directly, and the
# round-trip test starts it explicitly. An always-on subscriber would double-mirror.
config :server, start_consult_mirror: false

# In test the harness manages the repo lifecycle (fresh, migrated DB per run),
# so the application does not start it. The DB is the suite's own `tlon_test`,
# never the real one.
config :server, start_repo: false

# A fixed signing key for the stateless MCP tokens, so tests mint/resolve deterministically with
# no secret-file IO (Server.MCP.Secret reads this before touching disk).
config :server, token_secret: "test-only-token-secret-not-for-any-real-world-32b"

# Where workline artifacts are written and COMMITTED. Unset it falls back to the cwd — which is
# inside the ficciones checkout, so a test that approves a gate committed intent.md into the real
# repo (2026-09-18). A test that needs the artifact path makes its own throwaway git repo.
config :server, workline_root: "/nonexistent/tlon-test-workline"
