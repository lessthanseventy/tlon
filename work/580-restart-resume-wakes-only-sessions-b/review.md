# Review: 580-restart-resume-wakes-only-sessions-b

**Verdict: APPROVE** — branch `work/580-restart-resume-wakes-only-sessions-b` @ `4ea91945b291`, one commit, five files.

## What I read

The whole diff (`git diff origin/main...HEAD`), the surrounding sweeps in `staffing.ex` (`end_windowless`, `end_predating_tmux`, `has_window?`), `Session` schema, the test helpers, and the tech lead's read on the thread (hronir via tertius, msg #22476). No spec.md/plan.md exist for this workline; the brief is the spec.

## Spec compliance

1. **`Staff.interrupted/2` draws the line at `started_at < before`.** The witness:
   ```
   where: t.workspace_id == ^workspace_id and is_nil(s.ended_at) and not is_nil(s.thinking_since) and
            s.started_at < ^before
   ```
   Exactly the predicate asked for. The only caller passes `Staff.booted_at()`; no other caller of the old arity remains (grep over `server/lib`, `server/test`, docs).
2. **Boot time is a `:persistent_term` set once in `Application.start`,** before `init_fence`. Correct tool for write-once-read-often.
3. **Not tmux's clock.** `end_predating_tmux` is untouched and still keeps its own tmux-start cutoff. Good: a `server:restart` leaves tmux up, so the two clocks measure different things.
4. **Out of scope respected.** A post-boot windowless mid-turn session is left to `end_windowless` / #566, as hronir asked.

## Correctness

5. **The loop is actually broken.** The session each wake spawns registers after boot, so `started_at >= booted_at` and the next pass skips it. One restart, one wake.
6. **The epoch default is safe.** `booted_at/0` returns 1970 when unmarked, so `started_at < epoch` is false for every row: a node that somehow never marked ends nothing. Fail-closed, as the doc says.
7. **Microsecond `DateTime` against a `:utc_datetime` column** (`booted_at` keeps usec; `started_at` is second-precision). Ecto casts the param to the field type, truncating. `end_windowless` already does the identical thing with `idle_since`, and the suite exercises this path. No finding.
8. **Test isolation.** `staffing_test` is `async: false`; its setup pins boot a day ahead so every fixture predates it, and `on_exit` resets to now. Nothing leaks into async modules.

## Tests

9. Tests (a) and (b) are the two the tech lead asked for, and they discriminate: under the old `interrupted/1` the second pass in (a) would end `woken` and post a second "machine restarted" line, failing both `refute … ended_at` and the `count == 1`; (b)'s `mid` would be ended. The builder's caveat (the red run was a compile error, not behavioural red) stands; I did not run them against the old code either (no write access to revert), so this is reasoning, not measurement.
10. **Measured:** `menard run test --in server test/server/staffing_test.exs` → `{"ok":true,"tests":46,"failed":0}` (recorded, check event 14019). Verify's full `mise run check` passed at 20:36:43Z (CHECKS).

## Bench

No `bench_contrast` row in CHECKS; the diff touches no persona or profile. Nothing to report.

## Non-blocking

One stale load-bearing comment, listed as a follow-up: `end_windowless`'s "Mid-turn ones are resume_interrupted's" now holds only for sessions begun before boot. Fix on the branch is one line, or hand it to #566 where the gap it names lives.