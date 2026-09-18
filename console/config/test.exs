import Config

# The suites probe the degrade-and-log seams on purpose (BoomProbe render raises, read-seam
# fallbacks) — keep that noise out of the operator's real ~/.cache/aleph/crash.log.
config :console, crash_log_path: Path.join(System.tmp_dir!(), "aleph-test-crash.log")

# Don't run the app-global Console.Workspaces cache under test. It subscribes to the funes workspaces Bus at
# boot, so workspaces registered by the async DB tests (workspaces_test.exs) would leak into its cache and
# pollute Space.all/0 for the pure-render tests. Unstarted, fetch_workspaces/0 degrades to [] → the
# deterministic hardcoded [:orbis, :tlon] fallback. workspaces_test.exs starts its own local pids.
config :console, start_workspaces: false

config :server, Oban, testing: :manual

# No Repo → nothing for boot integrity to check; keep the one-shot out of the tree.
config :server, bootstrap: false

# Point the operator settings file away from the real ~/.config so the box's own overrides can
# never leak into test assertions; Console.Config tests pass explicit paths.
config :server, operator_config_path: "/nonexistent/aleph-test-config.json"
config :server, start_mcp: false

# aleph's own tests exercise the pure render path (panels → lines → composition) headlessly,
# with no DB. So when `mix test` boots funes as a dep, keep its Repo down — otherwise it would
# try to open a database aleph's test env never configures. PubSub still starts (harmless).
config :server, start_repo: false

# The hub loop (switchboard wake + MCP Bandit) must NOT start under test: no Repo to drain
# against, and a bound MCP port would collide across runs. aleph's tests are the pure render +
# reducer path (config.exs turns these on for the real `aleph.run` hub).
config :server, start_switchboard: false
