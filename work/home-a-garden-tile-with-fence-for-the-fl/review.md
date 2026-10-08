VERDICT: approve (partial scope — the fence is OPEN, see below)

Reviewed 4be1def (office/kit/home.ts, office/test/home.test.ts). Read the diff only; I did not run the gate myself. The server's verify run recorded `mise run check` green.

Correct:
- `garden` is added to `HomeTileKind` and `CATALOGUE`, appended last. `place()` therefore cycles street→garden→living, and the wrap back to living is tested.
- The save/load round trip with a garden next to a living tile is tested. Connectivity is unchanged because it is pure grid adjacency, so the drop rules are not affected.
- The change is surgical, with no stray edits. The tests cover the cycling order and persistence.

Open (not blocking this slice, but not done):
- The goal says "a garden tile (with fence)". Only the tile kind exists. There is no fence and no garden drawing. The builder reports there is no home-tile renderer at all, so nothing draws any tile kind from home.json. I could not find one either (grep for "street" hits only kit/home.ts and its test).
- No spec.md or plan.md exists on main or on the branch, so I could not check against a written spec. I judged against the goal line and the builder's note.
- The fence and garden art need a follow-up ticket that lands after a tile renderer exists (siblings #173 and #175 touch floor render). Whoever merges this should file it. Merging this as "garden tile with fence" would overstate what it does.
- The CATALOGUE order is the build-mode cycle order. Garden now sits between street and living, which is fine.