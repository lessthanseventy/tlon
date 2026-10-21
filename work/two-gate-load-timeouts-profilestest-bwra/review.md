# Review — two-gate-load-timeouts-profilestest-bwra

**Verdict: approve**

Two test-only changes for #517 (ProfilesTest bwrap budget, RolesTest builder fixtures), both faithful to tertius's spec in #10469. Surgical: only the two test files + pr.md, one commit per half as asked. 84/84 green on the targeted run; full `mise run check` exit 0 (350s); verify evidence recorded.

## bench/roles_test.exs:28 — builder graders concurrent
- `Task.async_stream` (ordered: false, timeout: :infinity) runs the 6 BEAM-booting graders side by side instead of serially. Each writes to its own `Path.join(tmp, t.id)`, so the concurrent `cp_r!`/`System.cmd` target distinct dirs — no collision.
- `timeout: :infinity` is safe: the outer test keeps ExUnit's 60s ceiling, and the measured cost is 3.0s. A crashing grader yields `{:exit, _}`, which the `{:ok, r}` map fails loudly rather than silently dropping. Good.
- Added `assert results != []` — closes the vacuous-pass hole (an empty `Roles.load` previously made the `for` assert nothing). Real improvement, on theme with the "passed vacuously against an empty thread" lesson.
- `code != 0` assertion preserved per grader. Compliant.

## profiles_test.exs:35 — 300→110 repos per grower
- Seeding dropped 300→110 in the three unbounded growers (mix, menard-scratch, tlon-scratch/other-seat), cutting ~1,100 serialized `mkdir_p` calls to ~430. The gate load is the thing being treated; the budget assertion is unchanged.
- The comment's arithmetic holds the "can still go red" line: (110 + 65) × 45 = 7875 > 7500, so a single grower re-added to a seat's write roots busts the budget. Red run recorded (192 repos, 11565 > 7500 with `~/.cache/mix` in the roots). The seats' actual roots exclude these caches (guarded by the sibling "no seat can write another seat's scratch" test at :57), so the test passes green at 110. Honest — the test still measures something.
- Comment is load-bearing (the *why* of 110, not just "slower"). Compliant.

No bugs, no security concerns. Non-blocking findings worth a ticket: none — the builder set is frozen, so `async_stream`'s default `max_concurrency` of 10 won't quietly throttle if it grows.

Ship it.