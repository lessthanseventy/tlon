# #505: the bwrap budget test times out at 60s under the full gate

Closes #505 (the test-cost half; the read-dir budget itself is already on main).

## What changed
- `server/test/server/profiles_test.exs`: each seat's scratch dir is seeded once, not once per archetype (the seeding ran 4 times for 2 seats × 2 archetypes).
- The same test gets `@tag timeout: 120_000` as a floor above ExUnit's 60s default. The assertion is unchanged; the budget it checks is the same.

## Not changed, and why
- `async: true` plus `Server.TestDB.clean!/0` in this module: the only async module that wipes the shared DB. Real, but switching it to `async: false` changes gate scheduling and needs its own measurement. Filed as its own ticket (#834).

## How it was checked
- `menard run test --in server test/server/profiles_test.exs`: 74 tests, 0 failures.
- The budget test alone: green (`profiles_test.exs:61`).
- Before/after wall time: not separable on this box. The load average was ~65 during both runs, and `menard`'s wrapper alone took about 2.5 min wall for ~2s of CPU. The test's own CPU time is small; the 60s timeout is load, not work in the test body.
- Gate: see the `tlon/check` status on the head sha.
