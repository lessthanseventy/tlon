# toys:refresh says why it failed, per pool, and stops before the schedule kills it (#625, part 2)

Part 2 of #625. Part 1 (the root cause on the host) is the operator's.

Schedule 11 (`toys:refresh`) was killed at 1800 s with empty output on 10-23/24/25. The old rpc made
34 model calls in a row and printed only at the end, and a 124 from `timeout` discarded the CLI's
stderr, so there was nothing to say why.

- `Server.ModelCli`: a timeout is `{:model_cli_timeout, s, stderr}`, so a hang still names what the CLI wrote. Callers and the judge test updated.
- `Server.ToyPool.refresh_cli/0`: the whole `toys:refresh` run. Each pool's line prints as it finishes; the run stops after 3 model timeouts in a row (3 × 120 s, well under 1800 s), says how many pools it did not try, and raises. `scripts/tlon-cli.sh toys` is now one call to it.
- `refresh_all_due/1` keeps its shape for callers and tests, and ends with `{:stopped, untried}` when the streak stops it.
- Docs that named `refresh_all_due` now name `refresh_cli`: `server/AGENTS.md`, `docs/manual/tasks.md`, the `toys:refresh` description in `tasks/server.toml`.

Ticket: closes #625 (part 2).

How checked:
- RED first, then GREEN, per commit: the ModelCli timeout test failed on the 2-tuple shape; the ToyPool tests failed on `refresh_cli/0` undefined. Both then passed.
- The stopped-run test stubs the model CLI to hang: 3 calls, the stop line, and the raise, in about 3 s (`model_cli_timeout_s` = 1).
- `menard run check --in server`: 2487 tests, 0 failures.
- Not checked live: a run against the real service's Ollama model. Unverified until the next scheduled run.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
