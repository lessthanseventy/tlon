# Review — tmp-leaks-server-jobs-and-tools-write-un (HEAD aa60af3)

**Verdict: APPROVE.** The fixes are correct, surgical, and follow the established patterns in both packages. The full gate is green on the branch (verify passed `mise run check`, office:check 802/0). The three open writers are correctly scoped out with reasoning. Merging this removes the `cast-file-`, `maintain-quiet-`, `needs-quiet-` and `needs-pause-` leaks; the rest are tracked.

## What's fixed (verified against the diff)

- **cast-file** (aa7773e, office): `cast-file.test.ts` now tracks each `mkdtemp` dir and `rmSync`s them in `afterEach` — the exact pattern already used by `whimsy-file.test.ts` and `hall.test.ts`. Consistent, not invented. Measured 5→0.
- **maintain-quiet / needs-quiet / needs-pause** (e706af3, server): the three config paths move from `System.tmp_dir!()` to `Path.expand("tmp")`, which is the same `tmp/` the test_helper already `rm_rf`s before/after the run. `test_helper.exs` now `mkdir_p!`s it up front so a test can write there. Matches the existing `@tag :tmp_dir` convention (git repos under `tmp/`). No collision: filenames stay unique by pid+unique_integer. Measured +1→0 for maintain-quiet.
- **hall / whimsy**: confirmed no new writes — those tests already clean up after each case; the /tmp entries are pre-fix leftovers (out of scope, operator's call to delete).

## Spec compliance

The ticket's done-when was: per-writer tests green, gate green, PR lists each prefix with writer and fix. All three met. The PR's per-prefix table names every writer from hronir's count with its state.

One gap against the ticket's *method* (not its done-when): the ticket asked for **test-first red-then-green per writer** — a test that goes red while a run leaves a new top-level `/tmp` entry, green after. The builder instead changed the existing tests' paths and measured leaks manually (counting entries before/after). That's a reasonable read for a cleanup like this, and the hardcoded `tmp/` paths are low-regression-risk, but there's no automated guard catching a future revert. Filed as a follow-up, not a block — the core fixes are done and the gate is green.

## Open items (named in the PR, tracked below)

- **tlon-smoke-job-\*.log** — production writer `lib/server/jobs/smoke.ex:16`, not a test. The log path is posted to the thread (smoke.ex:39,87) for the operator to read, so deleting it after a run breaks the link. Genuinely needs an operator decision on a persistent dir. This is the remaining piece of #560; the builder correctly left it rather than guess. Follow-up below.
- **menard-format / menard-told / menard-path** — confirmed menard's writer (hook.ex:208,223; format.ex:103; worker.ex:114), routed to #565 by tertius. Not tlon's to fix.
- **srt-mux-\*.sock** — Claude Code's sandbox, out of scope per ticket.

## Notes for the operator (non-blocking)

A grep shows the broader habit is still widespread: ~20 other server tests still write `*-pause-*`, `smoke-stub-*`, `sweep-recheck-*`, `strays-test-*`, etc. to `System.tmp_dir!()` (schedules_test, gateway_test, pause_test, switchboard_test, release_smoke_script_test, tickets_test, …), and office has more `mkdtemp` users (cast-sandbox, cast-view, hall-hire). None of those prefixes appeared in hronir's count, so they likely clean up via `on_exit`/`afterEach` — but they're the same trap this ticket just closed for the four named writers. Worth a sweep ticket if the /tmp pile returns; not this PR's job.