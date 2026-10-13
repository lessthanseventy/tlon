# Review — toy step 9, the hiring hall (thread 257), round 3

**Verdict: approve.** Both round-2 blocking findings are fixed test-first in `2b805f1` + `46b5a4d`, and the fixes match what I asked for; nothing new introduced in the delta (`5981c00..46b5a4d`: `kit/hall.ts`, `test/hall.test.ts`, `tui/main.ts` only).

## Round-2 findings, checked
1. **Maybe pile re-renders the name the card showed** — `maybe` now bakes `candidateOf(h, o).name` into the pile entry's overrides, so `takenNames` reads it straight from the entry and the pile row renders it regardless of what `roll` would pick under the current `taken`. Test "a pile entry re-renders with the name the card showed" covers the exact repro (bench `["funes"]`, hall seed 1).
2. **Hired name not carried onto the next card / not hired twice** — `pass` skips baking a locked `name` when it is in `taken`; `hallHire` refuses a taken name with a status line and passes with the hire counted as taken (so the stale `all.bench` can't leak the name onto the next card before `refresh`). Test "a pass past a hire: the locked name is used up…" covers the kit half. The `hallHire` refusal has no unit test (the TUI function isn't under test); filed as a follow-up, not blocking — the kit guard alone already prevents the double-look overwrite path.

## Verified
- `cd office && bun test test/hall.test.ts test/hall-view.test.ts test/sandbox.test.ts`: 37 pass, 0 fail; `bunx tsc --noEmit` clean (recorded).
- Verify stage's `mise run check` passed on the branch (brief, 13:19Z).
- Read `takenNames`, `roll`, `applyOverrides`, `candidateOf`, `hallCtx` end to end against the new code: the baked pile name wins over `roll`'s fresh pick via `applyOverrides`, and the pile row path (`main.ts` ~1576, `locks: {}`) renders it the same way.

## Non-blocking (follow-ups, filed)
- `hallHire`'s taken-name refusal has no test.
- `roll`'s `prev`/lock branch is unreachable from the app; locks are kept by `pass` baking overrides. One mechanism, not two.
- Spec §2 `e` (edit the look / soul from the hall) has no plan task and is not built; `s` is task 7 (blocked). Needs a home.
- `hall-pile` `x` re-implements `dropPile` inline.
- Minor wording: the refusal says "unlock the name" but a pile entry brought back carries the name as an override, not a lock; `pass` clears it either way.

## Still out of this branch, as agreed
Plan tasks 1, 2, 6, 7 wait on souls-step-2 (`Server.Soul`); the office's → says so and seats nobody. #65 stays open for that half.