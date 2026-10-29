# Review: Roster tie-break on Server.Trust record (#504) — c0e6f45

**Verdict: approve.**

Read: the one commit on work/roster-tie-break-on-server-trust-record (roster.ex, workline.ex, roster_test.exs, pr.md), against tertius's brief (#16503). Ran `menard --frozen run test --in server test/server/roster_test.exs`: 12 tests, 0 failures. CHECKS: `mise run check` passed on c0e6f45. No bench_contrast row.

1. **Spec compliance.** The witness, `pick/2`'s sort key: `{same_model?, below?, distance, miss?, -trust_rate(cand), i}`. The record is the last term before bench order, so it cannot outrank model, grade or specialty. Tests cover each precedence and the equal-records → bench-order fall-through. Matches the brief.
2. **Neutral when absent.** `trust_rate/1` is 0.5 for no `trust` key and for `led: 0` (the `when led > 0` guard), so a fresh seat is neither first nor last. Correct; no 0/0.
3. **Purity kept.** Roster reads only what the candidate carries; `restaff` and `suggest_lead` call `Server.Trust.record/1` per candidate (two queries each, bench-sized, at staffing time only). Acceptable.
4. **Scope.** `Trust.record` counts builds led, so for a reviewer or QA seat it is always `led: 0` → neutral: the tie-break only ever moves a build pick. Harmless, and as narrowed. `escalate` still passes no record (ireneo said so in #16532).

Non-blocking follow-ups below.