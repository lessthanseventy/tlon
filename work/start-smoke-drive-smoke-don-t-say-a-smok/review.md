# Verdict: approve

The send-back is fixed and the gate is green (`menard run check --in server`: 1967, 0 failed).
Continuation now waits on a building smoke only at `review`, and `building/2` drops a job queued
over 20 min ago so a stuck smoke can't silence the lead forever.

## What changed since d32fe1d

- `Smoke.building/2`: `state in ["available","scheduled","executing"]` (was + "retryable"), plus
  `j.inserted_at > ago(@building_minutes, "minute")` with `@building_minutes 20`.
- `Continuation`: `nil <- smoke_building(thread)` replaces `nil <- Server.Smoke.building(thread_id)`;
  `smoke_building/1` returns `Server.Smoke.building(id)` only at `review`, nil at every other stage.
- `workline_continuation_test.exs`: the silencing test moves to `review`; two new tests cover the
  plan-stage nudge and the 25-min stale job.

## Correctness

- `thread` is bound in the `with` chain (`%Thread{…} = thread <- Repo.get(Thread, thread_id)`)
  before `smoke_building(thread)` is called — the swap from `thread_id` is sound.
- `building/2`'s age bound uses `inserted_at` (queue time), the conservative read: a job slow to
  even start is treated as stuck. `building_error/2` still reports `attempted_at || inserted_at`,
  but only for jobs the bound hasn't excluded — no mismatch in practice.
- `ago(@building_minutes, "minute")` expands the module attribute to a literal at compile time; the
  bound is `inserted_at > now() - interval '20 minutes'`. Compiles and tests green.
- `start/5` still checks `held` before `queue`→`building`, so a smoke that's up reports its url; the
  building path runs only when nothing is held. Unchanged ordering, correct.
- All fragments parameterised; no injection surface.

## Tests

Red-first per the builder. "no nudge while the thread's smoke is building" now opens at `review`,
runs continuation 5× (no nudge), completes the job, and asserts the nudge resumes. New:
"a building smoke does not silence the lead outside review" (plan-stage, nudge posts) and
"a smoke job executing for over 20 minutes is stuck, not building" (25-min-old executing job at
review, nudge posts). The bound is tested on both sides — a fresh job still silences.

## Follow-ups (non-blocking)

The 20-min `inserted_at` bound lives in `building/2`, so it also governs drive_smoke/stop_smoke/
start_smoke, not just continuation
After 20 min a slow-but-real build becomes invisible to drive/stop ("no smoke is up") and a
same-ref start_smoke queues a second build beside the first. 20 min is generous for a smoke
(observed 2–7 min), so this is an acceptable edge, but the bound arguably belongs in the
continuation path rather than the shared lookup — worth a look if a slow machine ever trips it.

A building smoke can't be stopped (still open, ticket #536)
stop_smoke reports "building since <t> (job N)" but does not cancel — a building job has no os_pid
in meta, so there is nothing to TERM. Cancellation was never in #515's scope (visibility), but a
stop_smoke that can cancel a queued/building job would close the loop.

Same-ref start compares the ref string, not the resolved sha (still open, ticket #537)
building/2 matches args->>'ref', so a branch whose tip moved mid-build returns the old building
job for a "same-ref" start. Resolving ref→sha before the lookup would make the idempotency true
to the ticket's "same sha" ask.