# Review: floor-step-3-build-mode-and-the-first-ho (round 3)

**Verdict: approve**

## Scope

Reviewing the delta since the last approved round: commit `04eb942`, "office: remove() refuses a removal that would split the floor" — the fix for the connectivity gap this review's prior round (grader + reviewer) flagged in `remove()`.

## Findings

None blocking.

- `remove()` now mirrors `drop()`/`place()`: it computes `rest` and refuses (`refused: true`, no write, `home` untouched) when `connected(rest)` is false, exactly as requested. Verified by reading `office/kit/home.ts:82-89` — `connected(rest)` with `rest.length <= 1` is trivially true, so removing down to 0 or 1 tiles is never wrongly refused.
- Two new tests cover it: the disconnect-refusal case (remove the middle of a 3-in-a-row line, expect `refused` and `home` unchanged by reference) and a regression guard (dropping a carried tile back onto its own original cell still succeeds, i.e. `canPlace` doesn't reject a no-op).
- Ran `bun test test/home.test.ts` locally: 18 pass / 0 fail.
- `tsc --noEmit` reported clean per the builder's message; not independently re-run here, but the diff is a 3-line engine change plus tests, low risk of a type error.

## Carried-over non-blocking notes (from the prior approved round, still true, still not blockers)

1. Unbounded grid render if the cursor wanders far from the origin.
2. `place()` drops `rot` when cycling a kind at an occupied cell.
3. `main.ts` wiring (save-on-write-counter, `B`/undo key handling) has no drive-office end-to-end coverage — the pure engine is well tested, the TUI glue is not.

## Note on issue #4

The verify failures reported for this workline (`wide.test.ts` golden-hash, `pastimes.test.ts` cold-day path) are a pre-existing, deterministic failure on `origin/main` itself, confirmed by the builder and independently by `daneri` on both `origin/main` and the pre-fix commit `2d2c87a`. It is unrelated to this workline's diff (`office/kit/home.ts`, `office/tui/home.ts`, `office/tui/main.ts`, `office/test/home.test.ts` only) and is tracked separately as issue #4. Not a review blocker for this workline; it is a verify/CI-gate problem for the whole server, not a defect in this change.
