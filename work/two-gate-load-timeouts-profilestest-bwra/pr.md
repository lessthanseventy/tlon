# Two gate-load timeouts: ProfilesTest bwrap budget and Bench.RolesTest builder fixtures

Closes ticket #517 (issue #53). Both tests hit ExUnit's 60s timeout on a loaded gate (#310's verify).

- `profiles_test.exs`: the bwrap-budget test seeds 110 repos per unbounded grower, not 300. One grower in a
  seat's roots still breaks it alone: (110 + 65) * 45 = 7875 > 7500.
- `bench/roles_test.exs`: the builder graders (one BEAM boot each) run with `Task.async_stream`; the `code != 0`
  assertion is kept for each. Measured 3.0s, so no `@tag timeout`.

Checked: `menard run test --in server test/server/profiles_test.exs test/server/bench/roles_test.exs` green (84 tests).
The profiles test goes red with `~/.cache/mix` added to the seat roots (192 repos, 11565 > 7500; recorded as a failed check).
