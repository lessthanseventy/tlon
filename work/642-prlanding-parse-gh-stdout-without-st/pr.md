# PRLanding: parse gh stdout without stderr; say who queued the PR (#642)

Closes #642.

- `Server.PRLanding.view/3` and `unprotected/3` ran gh with `stderr_to_stdout: true` and then parsed stdout. Any stderr line on exit 0 (an auth hint, a deprecation notice) broke the `Jason.decode` or the exact `"false"` match, so `land_pr` refused a landable PR. Both calls now drop `stderr_to_stdout`, matching `scripts/land.sh`.
- `Server.MCP.Tool.LandPR` passes the calling seat as `:by` through `request/3` into `queue/5`. The queue's thread post reads "approved by X, queued by Y". `queue/4` and its existing tests are unchanged, since `queue/5` takes `opts` with a default.

Checked:
- RED first: a stub that prints a warning line on exit 0 only when `stderr_to_stdout` is requested; the PR was refused as `gh could not read the PR`. The "queued by its branch" test asserts `queued by lonnrot` and failed before the change.
- GREEN: `server/test/server/pr_landing_test.exs` 14 tests, 0 failures; full server suite `2497 passed, 0 failures`; `mix compile --warnings-as-errors` clean; `mix format --check-formatted` clean on the three changed files.
- `menard run check --in server` did not reach its tests: its format step fails with "Expected one or more files/patterns to be given to mix format", so the checks were run one by one as above.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
