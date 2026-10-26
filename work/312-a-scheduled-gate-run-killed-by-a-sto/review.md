# Review — #312 a scheduled run killed by a stop is `interrupted`, not red

**Verdict: approve.** Reviewed work/312-a-scheduled-gate-run-killed-by-a-sto at b062214 (7 commits over b17a8fb). The diff does what the ticket and the plan ask, every reader of `ScheduleRun.status` was checked, and the gate is green.

## Spec compliance

- A script killed by SIGTERM/SIGKILL (exit 143/137) closes its run as `interrupted`; the standing note says "interrupted (exit N)"; no Sheriff report (`code != 0 and not interrupted`). Ticket's ask met.
- `Jobs.Orphans` closes a restart-cut run as `interrupted`, not `failed`.
- `Release.Candidate.newest/1` skips interrupted runs: the sha reads "no check:main on …", the next run is the verdict, and an interrupted run cannot unseat an earlier pass on the same commit.
- 124 (timeout) and every other non-zero exit stay `failed`. Exit 130 stays failed by decision (fact 4207).
- Migration 20261026160000 widens `schedule_run_status_check`; the plan missed it, the builder caught it.

## Findings (verified)

1. **Timeout cannot masquerade as interrupted.** `collect/5` returns a literal `{124, out}` after `kill.()` and never reads the port's exit, so the TERM `kill_tree` sends on a timeout can't surface as 143. The existing 124 test still asserts `failed`.
2. **Orphans guard intact.** Only the written status changed; `status == "running"` still scopes the update. `pm.ex running?/1` matches `"running"` only, so an interrupted run no longer holds a restart or a cut.
3. **Candidate: one door.** Both `ran/3` and `elsewhere/1` go through `newest/1`, so neither the verdict line nor the "its last run was on" tail sees an interrupted run. Two new tests cover the no-verdict case and the no-unseat case.
4. **Migration is reversible in the right order.** `down` maps interrupted→failed before re-adding the narrower constraint. The constraint name matches 20261005000000_schedule.exs:34.
5. **Readers.** grep over server/lib and office/: room.ex passes status through to `/api/schedules/:id/runs`; office `data.ts` types widened; `runGlyph` gives interrupted its own ⊘ (inactive tone) rather than the running `…`. No doc under server/docs, docs/ or AGENTS.md names the old two-value set.
6. **Evidence.** CHECKS: `mise run check` exit 0 at 22:27Z (server 2197 tests / 0 failed, office 913 / 0). No bench_contrast row among the shown checks. The verify artifact froze at 80776f2; b062214 (pr.md, docs-only) landed after verify entry. The merge gate rebases and gates again, so that is covered.

## Notes, not blocking

- The office glyph is untested, as the builder said: `runGlyph` is a private const in main.ts. Typecheck covers the type. ⊘ vs ✗ is a shape difference, not colour alone, which fits the legibility constraint.
- T6 proved the 143 exit with a stand-in for bash alone. The real schedules (pm.ex:44–45) run `mise run check:main` / `mise run release:smoke` under `sh -c`; see follow-up.
