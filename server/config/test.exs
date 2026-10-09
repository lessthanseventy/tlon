import Config

# The suite's own database on the local Postgres, DROPPED and created fresh per run by test_helper —
# so two checkouts sharing one would delete it under each other mid-run. Each checkout gets its own:
# any git worktree uses tlon_test_<name>_<hash of its path>, the main checkout tlon_test.
# TLON_TEST_DATABASE names another (a second suite in the same checkout).
# The naming rule lives in Server.TestDatabaseName (config/support/), tested directly by
# test/server/test_database_name_test.exs — a config file itself can't be run by ExUnit.
Code.eval_file(Path.join(__DIR__, "support/test_database_name.exs"))
test_database = Server.TestDatabaseName.compute(__DIR__, System.get_env("TLON_TEST_DATABASE"))

# a cached toggle would outlive TestDB.clean! into the next test; with no cache there is nothing to bust
config :fun_with_flags, :cache, enabled: false
config :fun_with_flags, :cache_bust_notifications, enabled: false

# Oban never runs jobs on its own in test — a test performs them.
# No commit waits for the disk (synchronous_commit off): a test db needs none to outlive a crash,
# and the wait was most of the suite's time — every test commits dozens of rows.
config :server, Oban, testing: :manual

config :server, Server.Repo,
  database: System.get_env("TLON_TEST_DATABASE") || test_database,
  pool_size: 5,
  log: false,
  parameters: [synchronous_commit: "off"]

# The web endpoint is started by the suite that tests it (no listener); fixed secrets.
config :server, Server.Web.Endpoint,
  secret_key_base: String.duplicate("t", 64),
  # Bootstrap (seed + repair) is driven explicitly by its own suite; an app-boot
  # run against the harness-owned repo would race the per-test TestDB.clean!.
  # The suite is headless: recall's query embedding points at a port nothing listens on, so it
  # degrades to keyword relevance instantly instead of reaching a real ollama.
  server: false

config :server, bootstrap: false
config :server, embedding: [endpoint: "http://127.0.0.1:1/api/embed", timeout: 200]

# Test transcripts are written moments before they are imported; nothing here is a live session.
# Imported sessions are titled by a model CLI in prod; here there is none, so the first-line fallback
# answers unless a test points this at a stub.
config :server, import_live_window_s: 0
config :server, import_title_cmd: "/nonexistent/tlon-test-title-cli"

# The machine seed (Server.Seed.machine/0) is the box's own file; tests that want one pass a path.
# Point the operator settings file away from the real ~/.config so the box's own overrides can
# never leak into test assertions; tests that want one pass an explicit path.
config :server, machine_seed_path: "/nonexistent/tlon-test-seed.exs"
config :server, operator_config_path: "/nonexistent/tlon-test-config.json"
# The PM's release desk acts on the tlon checkout (Server.Release.PM): a test hands it a throwaway
# repo, so one that forgets can never cut a release of the real one.
config :server, release_root: "/nonexistent/tlon-test-release"

# The consult mirror is off in tests: the pure maybe_mirror tests call it directly, and the
# round-trip test starts it explicitly. An always-on subscriber would double-mirror.
config :server, start_consult_mirror: false

# In test the harness manages the repo lifecycle (fresh, migrated DB per run),
# so the application does not start it. The DB is the suite's own `tlon_test`,
# never the real one.
config :server, start_repo: false

# a wake's look-again for a swallowed Enter (Server.Arbiter.Tmux): off, but where a test turns it on
config :server, tmux_confirm_ms: []

# tmux runs as is in the suite; the systemd scope (Server.Tmux.run) is tested by switching it on
# A fixed signing key for the stateless MCP tokens, so tests mint/resolve deterministically with
# Where workline artifacts are written and COMMITTED. Unset it falls back to the cwd — which is
config :server, tmux_scope: false
# no secret-file IO (Server.MCP.Secret reads this before touching disk).
# inside the ficciones checkout, so a test that approves a gate committed intent.md into the real
# repo (2026-09-18). A test that needs the artifact path makes its own throwaway git repo.
config :server, token_secret: "test-only-token-secret-not-for-any-real-world-32b"
config :server, workline_root: "/nonexistent/tlon-test-workline"
