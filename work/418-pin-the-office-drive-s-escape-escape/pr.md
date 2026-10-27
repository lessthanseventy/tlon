# Pin the release smoke's Escape, Escape, c key order (#418)

Closes #418.

The office drive in `release-smoke` must leave the focused reply box with two Escapes before it presses `c`. The fix was 20d02d4, and nothing tested it.

## What changed

- `server/test/server/release_smoke_script_test.exs`: the drive run in the existing "waits for the title" test is lifted into `driven_args/1`. That test and a new sibling read the drive's args.
- The sibling asserts, anchored on `Enter`, that the keys after it are `[wait, "Escape", "Escape", "c"]`. It pins order, not just presence.

Test-only. `scripts/release-smoke.sh` is untouched.

## How it was checked

- RED: with one Escape dropped from the drive keys in `scripts/release-smoke.sh` (local, not committed), the new test fails at `release_smoke_script_test.exs:410`. The drive got `Escape, c`.
- GREEN: restored; `menard run test --in server test/server/release_smoke_script_test.exs` gives 26 tests, 0 failures.
- Gate: `menard run check --in server` gives 2266 tests, 0 failures.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
