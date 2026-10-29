# Review: office and home on one floor across a street, part (a) the floor (#602)

**Verdict: approve.** Branch `work/home-office-and-home-on-one-floor-across` @ `6dfb458` (9 commits: spec, plan, 6 code, pr.md). Part (a) only; (b) is a separate build, as the spec says.

## What I verified

1. Full gate at verify: `mise run check` exit 0 (office 958 pass, 0 fail). The four touched suites here: `bun test test/floor.test.ts test/home.test.ts test/homeart.test.ts test/wide.test.ts` — 101 pass, 0 fail (recorded as a check).
2. `test/golden.json` is untouched; the "office rows stay put" test asserts the with-home frame's first `bare.rgba.length` bytes equal the bare frame's. Spec done-when (golden unchanged with and without a home) holds.
3. The live check the builder skipped (pr.md says so): `office:drive` in sandbox mode with a scratch street+living `TLON_HOME` starts and runs. The viewport would not pan under tmux (filed, see follow-ups), so I rendered a `WideRoom(696)` frame with a 50-cell street row, living/bedroom/kitchen at row 16 and a garden at row 17 to PNG and looked at it: office rows unchanged on top, a full-width street row directly under the hall with the front door opening onto it, the four tiles at their cells, frame height 242 = `floorHeight`. One coordinate space, as specified.
4. Spec decisions 1–5 are each in the diff: `CELL`/`OFFICE_ROWS`/`cellPx` (grid), `defaultHome` (one-row street, office width), `paintFloor` with no pad or rebasing, `floorPlan`'s third param adding `tileBlocks` + `doors`/`walk`, `startBuild(home, top)`/`canPlace(…, top)` refusing the office rows. `loadFloor` shifts a legacy file in memory only; the test reads the file back unchanged.
5. bench_contrast row: "unmeasurable" (office/AGENTS.md is read by a seat, never loaded by the bench). Not green, not REGRESSION; not a finding and no habit from it.

## Findings (none block)

6. `floorPlan.walk(from, to)` ignores its arguments' direction: the chain is always street-cell-under-the-door → living, with `from` prepended and `to` appended. `walk(doors.home, doors.office)` would send the figure to the street under the office door, then to the living tile, then jump to the office door. Only (b) will call it; (b) must reverse the array or the function must honour direction. Follow-up.
7. `streetDoors` needs a street tile at the exact cell under the door for the *current* width (`floor((w-18)/CELL)`); `defaultHome` is sized to the width at the time build mode first opened. A wider terminal later loses `doors`/`walk` with no sign. Harmless in (a); (b) should say so on screen or extend the street. Follow-up.
8. `HOME_BLOCKS`' lane invariant (local x=0 clear) is tested unrotated only, as the plan allowed. A kitchen rotated 180° turns `{x:1,y:0,w:11,h:2}` into `{x:0,…}` and blocks the lane the walk uses. (b)'s route test will hit it if a rotated tile is in the chain. Follow-up.
9. Spec §(a).4 says "waypoint at door midpoint"; the implementation uses each tile's top-left lane corner. Functionally a path that crosses no block (the test walks it); naming only. No action.
10. `renderHome` paints the office rows as ground rather than "dimmed" raised cells. Distinguishable, and the test pins that the two differ. No action.

Docs: `office/AGENTS.md` updated in the same change (`paintFloor`, `loadFloor`, `OFFICE_ROWS`, `floorPlan`'s third param). pr.md is honest about what was and wasn't checked.