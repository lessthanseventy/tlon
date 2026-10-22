Verdict: APPROVE.

The change (commit 0fee35d, 5 files, +68/-8) is correct, spec-compliant, and well-tested. Office-only, no server change — matches the scope decision (#3483).

## What it does
A routine whose streak reaches 7 hangs a 4 px photo on the first living tile's top wall; the tier (7/30/100 → 1/2/3) reads as a 1–3 px bar under the photo, so it distinguishes by width, not colour (good for the operator's acuity — #13). Streak <7 hangs nothing, so a lost streak takes the photo down. Frames are derived from `streaks` and never stored. `MILESTONES` is one exported helper for the trophy shelf to reuse (#3482). Build mode now fetches `data.life(w)` so the wall is current (#3502).

## Spec compliance
- Milestones [7,30,100], one helper, derived-not-stored, <7 no frame — all match #3482.
- Paints on the first living tile (`home.tiles.find(kind==="living")`), ≤3 slots (`slice(0, floor(TILE/FRAME_SLOT))` = 3), build fetches life on entry — all match #3502.
- `streakFrames` input `Record<string,number>` matches `LifeStatus.streaks` exactly (types.ts:10); tsc clean.

## Tests
`streakFrames`: under-7, broken (0), 7→tier1, 30→tier2, 100→tier3, ordering, one-per-routine — all covered. `homeart`: frame changes pixels, empty = plain tile, fourth not drawn, higher tier differs, living-only. Verify gate green (842 pass, both frozen hours). RED-first documented.

## Branch
Already rebased onto origin/main (head 169c3e9): `origin/main..HEAD` is exactly the 2 #27 commits. The pr.md's "64 commits / rebase pending tertius" is resolved — the merge gate will rebase cleanly. No landing blocker.

## Follow-up (non-blocking)
- `readCard` case `"build"` does `lifeCard = await data.life(w)` without the `?? lifeCard` null-guard that the `"life"` case (line 598) uses. If the fetch returns null on build entry, `lifeCard` is wiped, so the wall (and the life card after exiting build) goes empty instead of keeping stale data. Minor inconsistency; the defensive `?? lifeCard` would match the sibling case.