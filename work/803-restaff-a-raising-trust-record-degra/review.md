# Review: #803 restaff — a raising Trust.record degrades to neutral (round 2)

**Verdict: approve.** The branch is at e8c12e1, the same head I approved last round; `git diff e8c12e1..work/803-… -- . ':!work/803-…'` is empty, and origin/main is still 7884bc5, the merge-base. Nothing to re-read in the code; the findings below carry over.

## Why it came back

The first landing bounced on `scripts/release-smoke.test.sh` ("a base with a listener steps on"), a script test this diff does not touch (scharlach, #28219; ticketed under #89). emma pushed a wait-widening copy (3a89b93), then dropped it on scharlach's word and force-pushed back to e8c12e1 (#28221). The verify gate's `mise run check` success was posted on 3a89b93, a strict superset of this head; the merge queue rebases and gates again at landing, so that is bookkeeping, not a gap in evidence for the code.

## What the diff does

The two `Server.Trust.record(&1.name)` lookups in `restaff/2` and `suggest_lead/4` become `with_trust/1`: the lookup alone sits in a `rescue` that logs a warning and returns the candidate without a `trust` key. `Server.Roster.trust_rate/1` falls through to 0.5 for a keyless candidate, so the tie-break is neutral, as the ticket asked. `restaff`'s outer `rescue -> restaff_miss` and `restaff_miss`'s silence for non-reviewer kinds are untouched (the ticket's stated limit).

## Findings

1. **Correct, minimal.** Before, the raise in the `Enum.map` lambda reached `restaff`'s outer rescue and the builder/planner handoff died unled and unannounced. After, the raise is caught per candidate, `Roster.pick` runs, `hand_to` posts the leads line.
2. **Test green on this head:** `menard run test --in server test/server/workline_test.exs:278` → `{"ok":true,"tests":1,"failed":0}` (recorded). `workline_test.exs` is `async: false`, so the `Application.put_env` seam is safe, and `on_exit` deletes it.
3. **Seam shape matches precedent** (`:arbiter`, `:crew` impl overrides).
4. **`escalate` has nothing to wrap on this base:** it passes no `trust:`. #520 adds that lookup and should route it through `with_trust/1`; uqbar is carrying that to #520 (#28200).
5. **`Trust.record/2` is one `Repo.all`,** so its failure mode is an exception the `rescue` catches; no `exit` path.
6. **CHECKS:** `mise run check` exit 0 on 3a89b93 (see above); the earlier exit 1 was the smoke flake, not this change. No `bench_contrast` row.

## Still open, non-blocking

- **Detectability (grader #28198, my #28204):** a lasting Trust failure leaves only a `Logger.warning`, nothing on the thread or to the sheriff. Filed as ticket #805 with the one-line `Server.Sheriff.report` patch and the test assert. uqbar declined a send-back for it (#28200); it stays a ticket.
