# Verdict: approve

A smoke that is building is now visible. `Server.Smoke.building/2` finds the thread's queued or
running smoke job with no url yet; `drive_smoke`/`stop_smoke` answer "building since <t> (job N)"
instead of "no smoke is up"; a `start_smoke` for the same ref returns that job instead of stacking
a second build; and `Continuation` treats a building smoke as waiting, like a verify job. All three
asks in ticket #515 are met.

## Spec compliance

No spec/plan docs on this branch — the ticket's three asks are the spec, and the pr.md maps to them:

1. drive/stop say "building since <t> (job N)" — `none/2` checks `building/1` in the nil-held path. ✓
2. same-ref start returns the building job — `queue/3` calls `building/2` with the ref. ✓
3. continuation silent while the thread's smoke builds — `nil <- Server.Smoke.building(thread_id)` in the `with` chain, short-circuits to the `_ -> :ok` catch-all. ✓

## Correctness

- `held` is checked before `building` in `start/5`'s cond, so a smoke that is already up still
  reports its url; the building path only runs when nothing is held. Right ordering.
- `none/2` returns the original fallback unchanged when nothing is building, so the not-building
  message is byte-identical to before — no regression for the common path.
- `queue/3`'s args map is the same shape the inline insert built (`Map.reject` of nil/[]), and
  `Jobs.Smoke.perform` reads `flags`/`fixtures` with `|| []`, so rejecting empty lists is safe.
- `building_error/2` uses `attempted_at || inserted_at`; an available job has no `attempted_at`, so
  it falls back to `inserted_at`. Both are UTC, so the `Z` suffix is honest.
- The `building` query states `["available","scheduled","executing","retryable"]` include two that
  are unreachable for smoke jobs: `max_attempts: 1` means a failed job is discarded, never
  `retryable`, and smoke jobs are never `scheduled`. Harmless dead branches, not worth a commit.
- All fragments are parameterised (`^to_string(thread_id)`, `^ref`); no injection surface.

## Tests

`jobs/smoke_test.exs` "a smoke still building": drive/stop say building with the job id; a same-ref
start returns the existing job (no second build); a different-ref start still queues.
`workline_continuation_test.exs`: no nudge while a smoke is building, nudge resumes once the job
completes. Red-first per the builder; `menard run check --in server` green (1965, 0 failed).

## Follow-ups (non-blocking)

A building smoke can't be stopped
stop_smoke reports "building since <t> (job N)" but does not cancel the build — a building job has
no os_pid in meta, so there is nothing to TERM. QA must wait for the build to come up (then stop) or
fail. That is within this ticket's scope (visibility, not cancellation), but a stop_smoke that can
cancel a queued/building job would close the loop.

Same-ref start compares the ref string, not the resolved sha
The builder flagged this: `building/2` matches `args->>'ref'`, so a branch whose tip moved mid-build
still returns the old building job for a "same-ref" start. The ticket's ask 2 says "same sha";
resolving ref→sha before the lookup would make the idempotency true to the ask.