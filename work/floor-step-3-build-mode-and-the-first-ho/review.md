## Verdict: approve

Reviewed the 4-commit diff on `work/floor-step-3-build-mode-and-the-first-ho` (`office/kit/home.ts`, `office/tui/home.ts`, `office/tui/main.ts`, `office/test/home.test.ts`). No `spec.md`/`plan.md` exist for this workline (expected — it started after those stages). Ran `bun test test/home.test.ts`: 13 pass, 0 fail, matching the verify-stage claim.

### What's correct
- `connected`/`canPlace`: straightforward BFS over grid adjacency, correctly excludes the tile-in-motion before checking for overlap vs. connectivity split. `place()` builds its "without" set from the *existing* tile at the cursor before calling `canPlace`, so it doesn't double-count — verified by tracing the catalogue-cycling test.
- The write-counter fix (`writes` field) is real: `pickUp`/`move`/refused `drop` leave `writes` unchanged, so the TUI's `mutate()` wrapper (`main.ts:787-792`) correctly skips `saveHome` for those paths — this is the exact bug described in the hronir build note, and it's covered by an explicit test (`expect(b.writes).toBe(0)` after pickup and after a refused drop).
- Carrying a tile across an app-quit is safe: `pickUp` never removes the tile from disk until a successful `drop`/`place`, so there's no data-loss window.
- `rotate` is cosmetic-only this step (every tile has doors on all sides per the home.ts header comment), consistent with "the first home tiles" scope.
- Traced undo interacting with a concurrently-carried tile for a duplication bug — none found: any history snapshot is always taken *after* the carried tile has already been excluded from `home.tiles`, so undo can't reintroduce a duplicate of what's being carried.

### Minor, non-blocking
- `main.ts:822` — the `u` (undo) key handler calls `saveHome(build.home)` unconditionally, bypassing the `wrote` check every other action in this card goes through (`mutate()`, `main.ts:787-791`). When `undo` is a no-op (empty history, e.g. first action in a fresh session), this still writes home.json — harmless since the content is identical, but it's an inconsistency with the write-counter discipline established by the prior bug fix. Worth a follow-up, not a blocker.
- `remove()` doesn't check connectivity before taking a tile off the floor, so it can split the floor into disconnected pieces (undo-able, but the split is live until then). The code's own header comment scopes the "stays one piece or refused" invariant to drops/placement, not removal, so this isn't a spec violation — just worth knowing if a later step assumes the floor is always contiguous.

Nothing here rises to request_changes. Approving.
