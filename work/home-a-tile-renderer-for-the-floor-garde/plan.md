# Plan — home annex: placed home tiles drawn in the live room (ticket #43, thread 192)

Decision (operator, 2026-10-08): option B. Build mode's renderer (`TILE_ART`, `paintTile`, `renderHome`;
garden+fence+street art) already landed (f055d52…05289a8, b7bc55e); this adds the missing half: outside
build mode the wide room shows the home. Scope: **an annex strip below the office**, painted with the
existing `paintTile`. NOT in scope: walking/pets in the home, `at` applied to office tiles, rail room,
mailbox/weather art, street letters (#185/#172 plug in by adding `TILE_ART` keys — already the hook).

Invariant: with no home tiles the frame is byte-identical → `test/golden.json` does NOT change.
Paths relative to repo root; run `cd office && bun test <file>`; gate `mise run office:check` then
`mise run check` (unsandboxed). One commit per task; trailer per AGENTS.md (your model).

Layout: annex height = `rows*CELL + 2*ANNEX_PAD` (CELL=14, ANNEX_PAD=8, from `kit/homeart.ts`); starts at
y=`WIDE_H`; tiles keep their grid-relative positions, left-aligned at x=ANNEX_PAD.

## Task 1 — `annexHeight` + `paintAnnex` (kit)
Files: `office/kit/homeart.ts`, `office/test/homeart.test.ts`.
Test first (append):
```ts
import { annexHeight, paintAnnex, ANNEX_PAD } from "../kit/homeart"
describe("annex", () => {
  const one = { tiles: [{ kind: "garden", at: [3, 5] }] } as Home
  test("no tiles → no height, nothing painted", () => {
    expect(annexHeight({ tiles: [] })).toBe(0)
    const c = new Canvas(40, 40), before = Buffer.from(c.rgba).toString("hex")
    paintAnnex(c, { tiles: [] }, 0); expect(Buffer.from(c.rgba).toString("hex")).toBe(before)
  })
  test("height covers the tile rows; a tile paints where paintTile would", () => {
    expect(annexHeight(one)).toBe(14 + 2 * ANNEX_PAD)
    const c = new Canvas(60, annexHeight(one)); paintAnnex(c, one, 0)
    const ref = new Canvas(TILE, TILE); paintTile(ref, 0, 0, one.tiles[0]!)
    const at = (cv: Canvas, x: number, y: number) => Buffer.from(cv.rgba).readUInt32LE((y * cv.width + x) * 4)
    expect(at(c, ANNEX_PAD + 1 + 5, ANNEX_PAD + 1 + 5)).toBe(at(ref, 5, 5))
  })
})
```
(Check `Canvas` exposes `width`; if not use the test's own `w`.) Red → implement:
```ts
export const ANNEX_PAD = 8
const bounds = (h: Home) => ({ x0: Math.min(...h.tiles.map((t) => t.at[0])), y0: Math.min(...h.tiles.map((t) => t.at[1])), y1: Math.max(...h.tiles.map((t) => t.at[1])) })
/** px height of the strip that shows `home` under the office: 0 when it has no tiles */
export const annexHeight = (h: Home) => h.tiles.length ? (bounds(h).y1 - bounds(h).y0 + 1) * CELL + 2 * ANNEX_PAD : 0
/** paints the home on `c` from row `y`: ground, then every tile via `paintTile` (a missing kind draws plain). Canvas clips what overruns the width. */
export function paintAnnex(c: Canvas, h: Home, y: number) {
  if (!h.tiles.length) return
  const { x0, y0 } = bounds(h)
  c.px(0, y, c.width, annexHeight(h), ROLE.ground)
  for (const t of h.tiles) paintTile(c, ANNEX_PAD + (t.at[0] - x0) * CELL + 1, y + ANNEX_PAD + (t.at[1] - y0) * CELL + 1, t)
}
```
Verify Canvas clips out-of-bounds `px` (read `kit/canvas.ts`); if it doesn't, clip in `paintAnnex`.
Done: `bun test test/homeart.test.ts` green. Commit "office: paintAnnex — the home as a strip of tiles".

## Task 2 — WideRoom draws the annex
Files: `office/rooms/wide.ts`, `office/test/wide.test.ts`.
Test first: `new WideRoom(696)` — (a) default render height === `WIDE_H` (existing assertion at wide.test.ts:21 keeps passing);
(b) after `room.setHome({tiles:[{kind:"garden",at:[0,0]}]})` render height === `WIDE_H + annexHeight(home)` and the
top `WIDE_H` rows hash equal to the no-home render of the same seeded scene (use `seeded`/`office`/`focus`/`measure` from `test/golden.ts`).
Implement in `wide.ts`: `private home: Home = { tiles: [] }`; `setHome(h: Home) { this.home = h }`;
`get height() { return WIDE_H + annexHeight(this.home) }`; in `render` use `new Scene(W, this.height, this.tick)` (keep
`const H = WIDE_H` for office drawing so nothing else moves) and, just before `return sc.finish()`, `paintAnnex(sc.cv, this.home, WIDE_H)`.
(Use `Home` from `../kit/home`, not `../kit/tiles`.) Done: `bun test test/wide.test.ts test/golden…` green, golden.json untouched
(`git diff --stat office/test/golden.json` empty). Commit "office: the wide room carries the home below the office".

## Task 3 — the TUI loads and shows it
Files: `office/tui/main.ts`.
- `let homeNow = loadHome()` near `petsNow` (line ~110); in `room()` (line 133) add `if (r instanceof WideRoom) r.setHome(homeNow)` beside `setPets`.
- When build mode is left (`!building && homeShown`, line ~1242): `homeNow = loadHome(); rooms.forEach((r) => r instanceof WideRoom && r.setHome(homeNow))`.
- `layoutScreen` line 1207: floor height for the wide room = `room().height` instead of `WIDE_H` (keep the scale loop on line 1201 on `WIDE_H` — the annex scrolls, it must not shrink the office). `room()` there is the wide room when `wide` is set; guard `instanceof WideRoom`.
No new unit test (glue); verified in Task 4. Done: `mise run office:check` green. Commit "office: the TUI shows the home under the office".

## Task 4 — drive it, docs
Files: `office/AGENTS.md` (the `homeart.ts` line in `kit/`, and `wide.ts`: "a home from home.json hangs below as an annex").
Use the `drive-office` skill with `TLON_HOME=<tmp>/home.json` holding a garden at [0,0], a street at [0,1], a living at [1,0]:
scroll down (pan keys) to the annex, screenshot, confirm garden+fence, street and living render; then `B`, drop a tile, Esc, confirm the annex updates.
Also run with the file absent: room unchanged. Paste outcome in the review. Commit docs "docs: office AGENTS — the home annex".
Final: `mise run check` green; golden.json diff empty.

## Risks / open
- `build_mode` flag is off on the live service, so the drive needs a scratch server with it on (Task 4 may report unverified for the `B` leg).
- wcag.test.ts labels only the office region; the annex has no text, so no new contrast risk.
- Annex wider than the room clips at the right edge (acceptable now; wide homes are rare under GRID_MAX 15 cells = 210px < WIDE_MIN_W).
