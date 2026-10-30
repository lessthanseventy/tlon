# Scratch smoke gets its own operator config (TLON_CONFIG)

A scratch smoke's Settings edits were writing the operator's real `~/.config/tlon/config.json`,
and it started from whatever that file held rather than from defaults. The scratch node inherited
the operator's file because `scripts/release-smoke.sh` never told it otherwise. #353 fixed only the
TUI side.

## What changed

- `Server.OperatorConfig.path/0` reads the Application env first, then `TLON_CONFIG`, then the XDG
  default. The Application env still wins, so the test envs are unaffected.
- `scripts/release-smoke.sh` starts the scratch node with `TLON_CONFIG="$dir/config.json"` under its
  build dir. That file does not exist yet, so the node reads no overrides and every knob is at its
  default. The `unset TLON_*` sweep runs before the node start, and the variable is set inline on the
  start command, so the sweep does not clear it.
- XDG_CONFIG_HOME is not moved, because `Server.Soul` shares that directory.

## Ticket

Closes #640.

## How it was checked

- RED first: both new tests failed for the right reason before the change. `path/0` ignored
  `TLON_CONFIG`, and the smoke script's node start carried no `TLON_CONFIG`.
- GREEN: `mix test test/server/operator_config_test.exs test/server/release_smoke_script_test.exs`
  reports 40 passed. `bash -n scripts/release-smoke.sh` is clean. `mix format --check-formatted` is clean
  on the three changed Elixir files.
- New tests: `Server.OperatorConfigPathTest` covers the precedence chain. The smoke script test asserts
  the node start line carries `TLON_CONFIG` under the build dir.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
