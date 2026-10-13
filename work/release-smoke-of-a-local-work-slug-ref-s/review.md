APPROVE

Verified: scripts/release-smoke.sh change + new tests; ran `menard run test --in server test/server/release_smoke_script_test.exs` → ok, 6 tests, 0 failed.

- Fix is minimal and correct: a failed origin fetch is fatal only when `$1` is not an existing `refs/heads/<arg>`; empty `$1` (origin/main default) still fails, tested.
- A warning line is printed so a stale local ref is not silent.
- Tests cover both directions (local ref proceeds past the fetch; origin/main still fails).

Nit (non-blocking): the tests hardcode port 4599; overlapping suite runs would collide.