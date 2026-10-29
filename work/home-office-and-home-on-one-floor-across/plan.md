# Plan: office and home on one floor across a street, with the clock-out walk (#602)

Spec: `spec.md` in this folder. All paths are under `office/`. Every task is one commit, test first.
Run tests with `bun test test/<file>` from `office/` (menard is Elixir-only). The gate is `mise run office:check`, unsandboxed.
Part (a) = tasks A1–A7, lands as its own PR(s). Part (b) = B1–B8, branches from (a) once it is on main. They touch the same files, so never in parallel.
Split (a) into two PRs: (a1) = A1–A4 (coordinates + render), (a2) = A5–A7 (sim + build mode).

## Facts the engineer needs (read from the tree)

- `kit/floor.ts` `floorPlan(home, w)` takes `kit/tiles.ts` `Home` (OFFICE tile kinds, `DEFAULT_OFFICE`). It is NOT the home-tile `Home` of `kit/home.ts` (`living`, `street`, ...). Do not merge the types. `floorPlan` gets a third, optional param: the home tiles.
- `rooms/wide.ts`: `widePlan(w) = floorPlan(DEFAULT_OFFICE, w)`; the `WideRoom` constructor calls `super(widePlan(width))`; the sim's `protected plan` is reassignable. `setHome(h)` (line ~499) stores the home. `WIDE_H = 200`, `HALL = 191`, `BAND = 44`. The front door is `plan.door = {x: w-18, y: HALL}`; it is drawn at `W-12`.
- `kit/homeart.ts`: `TILE = 12`, `CELL = TILE + 2 = 14` (not exported), `paintAnnex` / `annexHeight` / `ANNEX_PAD` draw the home as a strip below the office. `renderHome` is the build grid (its own Frame, not the floor).
- `kit/home.ts`: build mode engine. `tui/home.ts`: `loadHome` / `saveHome` for `home.json`.
- `tui/main.ts`: `homeNow = loadHome()` (l.288), build mode opens with `startBuild(loadHome())` (l.~1579), live re-read at l.~2140. `h` and `o` are already keys in scope `card:home` (`tui/keys.ts` 114, 122) — (b) binds at room scope only.
- Golden: `test/golden.json` hashes of the office-only frame. With no home set the frame must not change. Never re-hash golden in this work.

## Decisions I made (shout if wrong)

1. Pixel origin of home cells: `cellPx([cx,cy]) = [cx*CELL + 1, WIDE_H + (cy - OFFICE_ROWS)*CELL + 1]`. So row `OFFICE_ROWS` starts exactly at the office's bottom edge (no 10 px dead gap, since `15*14 = 210 > 200`). "Absolute cells" still holds for the grid; only the px origin is anchored at `WIDE_H`.
2. `OFFICE_ROWS = 15` (= ceil(200/14)), defined in `kit/home.ts` and checked against `WIDE_H` by a test (home.ts must not import wide.ts: cycle).
3. A tile on a row `< OFFICE_ROWS` is "overlapping the office" (the office spans the full width). Legacy files shift so the topmost row is `OFFICE_ROWS + 1` (spec's number), in memory only.
4. Build mode's reserve is a parameter (`top`, default 0), so the existing `home.test.ts` passes unchanged; only `main.ts` passes `OFFICE_ROWS`.
5. Default preset appears only when build mode opens on an empty home (an absent `home.json` still draws nothing and the golden holds).
6. Home furniture blocks keep local x = 0 (the left lane column) clear so a walk can pass at the tile's left edge; a test enforces it.

---

# PART (a) — the floor

## A1. Grid constants and pure geometry in `kit/home.ts`

Test first, append to `test/home.test.ts`:

```ts
import { CELL, OFFICE_ROWS, belowOffice, cellPx, floorHeight } from "../kit/home"
import { WIDE_H } from "../rooms/wide"
import { TILE } from "../kit/homeart"

describe("floor geometry", () => {
  test("the office block is ceil(WIDE_H / CELL) rows and a cell is a tile plus a border", () => {
    expect(OFFICE_ROWS).toBe(Math.ceil(WIDE_H / CELL))
    expect(CELL).toBe(TILE + 2)
  })
  test("cellPx: row OFFICE_ROWS starts at the office's bottom edge", () => {
    expect(cellPx([0, OFFICE_ROWS])).toEqual([1, WIDE_H + 1])
    expect(cellPx([2, OFFICE_ROWS + 1])).toEqual([2 * CELL + 1, WIDE_H + CELL + 1])
  })
  test("floorHeight: office alone, or down to the lowest tile's bottom", () => {
    expect(floorHeight({ tiles: [] })).toBe(WIDE_H)
    expect(floorHeight({ tiles: [{ kind: "street", at: [0, OFFICE_ROWS] }] })).toBe(WIDE_H + CELL)
    expect(floorHeight({ tiles: [{ kind: "living", at: [0, OFFICE_ROWS + 2] }] })).toBe(WIDE_H + 3 * CELL)
  })
  test("belowOffice shifts a legacy home so its top row is OFFICE_ROWS + 1, and leaves a placed one alone", () => {
    const legacy = { tiles: [{ kind: "living" as const, at: [0, 0] as [number, number] }, { kind: "kitchen" as const, at: [1, 0] as [number, number] }] }
    expect(belowOffice(legacy).tiles.map((t) => t.at)).toEqual([[0, OFFICE_ROWS + 1], [1, OFFICE_ROWS + 1]])
    expect(legacy.tiles[0]!.at).toEqual([0, 0]) // input untouched
    const placed = { tiles: [{ kind: "street" as const, at: [0, OFFICE_ROWS] as [number, number] }] }
    expect(belowOffice(placed)).toBe(placed)
  })
})
```

Code in `kit/home.ts` (add after the types; `WIDE_H` is not imported — `floorHeight` takes it as a default of 200 documented, or better a module constant `OFFICE_H = 200` that the test asserts equals `WIDE_H`; use that):

```ts
export const CELL = 14
/** px height of the office block; rooms/wide.ts WIDE_H, asserted equal in test/home.test.ts */
export const OFFICE_H = 200
/** cell rows the office occupies from the floor's top: a home tile on a row above this overlaps it */
export const OFFICE_ROWS = 15

/** top-left px of a cell's tile on the floor: row OFFICE_ROWS starts at the office's bottom edge */
export const cellPx = ([cx, cy]: Pt): Pt => [cx * CELL + 1, OFFICE_H + (cy - OFFICE_ROWS) * CELL + 1]

/** the whole floor's px height: the office, or down to the lowest home tile */
export function floorHeight(h: Home): number {
  if (!h.tiles.length) return OFFICE_H
  return Math.max(OFFICE_H, OFFICE_H + (Math.max(...h.tiles.map((t) => t.at[1])) - OFFICE_ROWS + 1) * CELL)
}

/** a home saved before the office was on the floor sits at the origin: shift it in memory (never on disk) below the office */
export function belowOffice(h: Home): Home {
  const top = Math.min(...h.tiles.map((t) => t.at[1]))
  if (!h.tiles.length || top >= OFFICE_ROWS) return h
  const dy = OFFICE_ROWS + 1 - top
  return { ...h, tiles: h.tiles.map((t) => ({ ...t, at: [t.at[0], t.at[1] + dy] as Pt })) }
}
```

Also change the test import of `WIDE_H` to also assert `OFFICE_H === WIDE_H` (add to the first test).
Done when: `bun test test/home.test.ts` green. Commit: "office: the floor's grid — CELL, OFFICE_ROWS, cellPx, floorHeight, belowOffice".

## A2. `homeart.ts`: `paintFloor` replaces `paintAnnex`

Test first — replace the `describe("annex")` block in `test/homeart.test.ts` (and its `ANNEX_PAD`/`annexHeight`/`paintAnnex` imports):

```ts
describe("floor", () => {
  const one = { tiles: [{ kind: "garden" as const, at: [0, OFFICE_ROWS] as [number, number] }] }
  test("no tiles → nothing painted", () => {
    const c = new Canvas(60, 60), before = Buffer.from(c.rgba)
    paintFloor(c, { tiles: [] })
    expect(Buffer.from(c.rgba).equals(before)).toBe(true)
  })
  test("a tile paints where paintTile would, at its absolute cell, with no pad", () => {
    const c = new Canvas(60, floorHeight(one)), ref = new Canvas(60, floorHeight(one))
    paintFloor(c, one)
    const [x, y] = cellPx([0, OFFICE_ROWS])
    paintTile(ref, x, y, one.tiles[0]!)
    for (let j = 0; j < TILE; j++) for (let i = 0; i < TILE; i++) {
      const k = ((y + j) * 60 + x + i) * 4
      expect([...c.rgba.slice(k, k + 4)]).toEqual([...ref.rgba.slice(k, k + 4)])
    }
  })
})
```

Code in `kit/homeart.ts`: import `CELL, cellPx` from `./home` (delete the local `const CELL`); delete `ANNEX_PAD`, `bounds`, `annexHeight`, `paintAnnex`; add:

```ts
/** paints the home's tiles on the floor canvas at their absolute cells (the office rows above are the room's own). Canvas clips what overruns the width. */
export function paintFloor(c: Canvas, h: Home) {
  if (!h.tiles.length) return
  for (const t of h.tiles) { const [x, y] = cellPx(t.at); paintTile(c, x, y, t) }
}
```

The ground under the tiles: `WideRoom.render` fills it (A3). Update the `homeart` header comment and the `kit/` bullet in `office/AGENTS.md` ("`paintAnnex` the placed tiles as a strip" -> "`paintFloor` the placed tiles at their absolute cells").
Done when: `bun test test/homeart.test.ts` green (wide.ts still compiles only after A3 — do A2 and A3 in one working session, commit each once green; if the typecheck blocks, A2+A3 are one commit).

## A3. `WideRoom` draws the floor, height grows by the real extent

Test first — replace the "annex" test in `test/wide.test.ts` (and the `annexHeight` import):

```ts
  test("a home on the floor below the office: the office rows stay put, height is the floor's real extent", () => {
    const home: Home = { tiles: [{ kind: "street", at: [0, OFFICE_ROWS] }, { kind: "garden", at: [0, OFFICE_ROWS + 1] }] }
    const a = viewOf(office(3), 1), now = new Date(2026, 9, 5, 21, 0)
    const shot = (h?: Home) => seeded(7, () => {
      const room = new WideRoom(696)
      if (h) room.setHome(h)
      for (let i = 0; i < 50; i++) room.step(a)
      return room.render(a, focus, measure, now)
    })
    const bare = shot(), withHome = shot(home)
    expect(bare.height).toBe(WIDE_H)
    expect(withHome.height).toBe(floorHeight(home))
    expect(withHome.height).toBe(WIDE_H + 2 * CELL)
    expect(Buffer.from(withHome.rgba.slice(0, bare.rgba.length)).equals(Buffer.from(bare.rgba))).toBe(true)
  })
```

Code in `rooms/wide.ts`: imports `floorHeight` from `../kit/home`, `paintFloor` from `../kit/homeart`; `get height() { return floorHeight(this.home) }` (line ~500); where `paintAnnex(sc.cv, this.home, WIDE_H)` is (line ~605) write `if (this.home.tiles.length) sc.cv.px(0, WIDE_H, this.width, this.height - WIDE_H, ROLE.ground); paintFloor(sc.cv, this.home)`. Keep `setHome` as is for now (A5 extends it).
Done when: `bun test test/wide.test.ts` green incl. the golden test (`OFFICE_TEST_HOUR=3` and `15`). Commit: "office: the home is drawn on the floor at its absolute cells (paintFloor)".

## A4. Loading: legacy shift, default preset, wiring in `main.ts`

Test first, append to `test/home.test.ts` (file-level helpers: use a tmp path under `process.env.TMPDIR`):

```ts
import { loadFloor } from "../tui/home"
import { defaultHome } from "../kit/home"
test("loadFloor shifts a legacy file below the office and leaves the file on disk untouched", () => {
  const path = `${process.env.TMPDIR ?? "/tmp"}/home-${Date.now()}.json`
  const raw = JSON.stringify({ tiles: [{ kind: "living", at: [0, 0] }] })
  writeFileSync(path, raw)
  expect(loadFloor(path).tiles[0]!.at).toEqual([0, OFFICE_ROWS + 1])
  expect(readFileSync(path, "utf8")).toBe(raw)
})
test("defaultHome: a street row the office's width, the rooms in a row under it, one piece", () => {
  const h = defaultHome(50)
  expect(h.tiles.filter((t) => t.kind === "street").map((t) => t.at)).toEqual(Array.from({ length: 50 }, (_, i) => [i, OFFICE_ROWS]))
  expect(h.tiles.find((t) => t.kind === "living")!.at).toEqual([0, OFFICE_ROWS + 1])
  expect(connected(h.tiles)).toBe(true)
})
```

Code:
- `kit/home.ts`: `export const defaultHome = (cols: number): Home => ({ tiles: [...Array.from({ length: cols }, (_, i): HomeTile => ({ kind: "street", at: [i, OFFICE_ROWS] })), { kind: "living", at: [0, OFFICE_ROWS + 1] }, { kind: "bedroom", at: [1, OFFICE_ROWS + 1] }, { kind: "kitchen", at: [2, OFFICE_ROWS + 1] }, { kind: "bathroom", at: [3, OFFICE_ROWS + 1] }] })`
- `tui/home.ts`: `export const loadFloor = (path: string = HOME_PATH): Home => belowOffice(loadHome(path))` (import `belowOffice`).
- `tui/main.ts`: l.288 and l.~2140 `loadHome()` -> `loadFloor()`; l.~1579 `build = startBuild(...)` — wired in A7 (needs `top`). Import `loadFloor`.

Done when: `bun test test/home.test.ts test/wide.test.ts` green; `bun run typecheck` green. Commit: "office: a saved home loads below the office; a default home preset".

## A5. Sim: home tiles' blocks, offset by their cell

Test first, new `test/floor.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { CELL, HOME_BLOCKS, OFFICE_ROWS, cellPx } from "../kit/home"
import { widePlan } from "../rooms/wide"
import { floorPlan } from "../kit/floor"
import { DEFAULT_OFFICE } from "../kit/tiles"
import { office } from "./golden"

const blocksOf = (tiles: Parameters<typeof floorPlan>[2], w = 696) => {
  const p = floorPlan(DEFAULT_OFFICE, w, tiles)
  return p.blocks(p.layout(viewOf(office(3), 1)))
}

describe("home tiles on the sim's floor", () => {
  test("a tile at [0, OFFICE_ROWS+1] adds its footprint at the cell's origin", () => {
    const base = blocksOf({ tiles: [] }), got = blocksOf({ tiles: [{ kind: "living", at: [0, OFFICE_ROWS + 1] }] })
    const [x, y] = cellPx([0, OFFICE_ROWS + 1])
    expect(got.length).toBe(base.length + HOME_BLOCKS.living.length)
    for (const b of HOME_BLOCKS.living) expect(got).toContainEqual({ x: x + b.x, y: y + b.y, w: b.w, h: b.h })
  })
  test("a tile two cells right is offset by 2*CELL in x", () => {
    const a = blocksOf({ tiles: [{ kind: "living", at: [0, OFFICE_ROWS + 1] }] }), b = blocksOf({ tiles: [{ kind: "living", at: [2, OFFICE_ROWS + 1] }] })
    expect(b.slice(-HOME_BLOCKS.living.length).map((r) => r.x - 2 * CELL)).toEqual(a.slice(-HOME_BLOCKS.living.length).map((r) => r.x))
  })
  test("no home tiles → the plan is the office's, block for block", () => {
    expect(blocksOf({ tiles: [] })).toEqual(blocksOf(undefined))
  })
  test("local x=0 stays clear and every block sits inside its tile (the walking lane)", () => {
    for (const rs of Object.values(HOME_BLOCKS)) for (const r of rs) { expect(r.x).toBeGreaterThanOrEqual(1); expect(r.x + r.w).toBeLessThanOrEqual(12); expect(r.y + r.h).toBeLessThanOrEqual(12) }
  })
  test("rotation turns a footprint with the sprite", () => {
    const rot = blocksOf({ tiles: [{ kind: "bedroom", at: [0, OFFICE_ROWS + 1], rot: 90 }] }).slice(-HOME_BLOCKS.bedroom.length)
    const [x, y] = cellPx([0, OFFICE_ROWS + 1]), b = HOME_BLOCKS.bedroom[0]!
    expect(rot[0]).toEqual({ x: x + (12 - b.y - b.h), y: y + b.x, w: b.h, h: b.w })
  })
})
```

(The "x=0 clear" test fails for sprites that run to col 0 — then shrink that block to start at x=1; blocks are approximate footprints of the sprite's furniture, not pixel-perfect. Rotating can move a block to col 0; apply the lane test to rotation 0 only and say so in the comment.)

Code in `kit/home.ts`:

```ts
import type { Rect } from "./tiles"
/** each home tile's furniture as tile-local px rects (from the sprites in homeart.ts); local x=0 stays clear — the lane a walk takes down a tile's left edge. street/garden/bathroom floor is open. */
export const HOME_BLOCKS: Record<HomeTileKind, Rect[]> = {
  living: [{ x: 1, y: 6, w: 10, h: 4 }],
  kitchen: [{ x: 1, y: 0, w: 11, h: 2 }, { x: 3, y: 4, w: 6, h: 3 }],
  bathroom: [{ x: 1, y: 1, w: 4, h: 5 }, { x: 10, y: 2, w: 2, h: 2 }],
  bedroom: [{ x: 1, y: 1, w: 6, h: 8 }],
  street: [],
  garden: [{ x: 1, y: 3, w: 11, h: 2 }, { x: 1, y: 6, w: 11, h: 2 }],
}

/** a footprint turned clockwise with its tile (the sprite is 12×12) */
function turn(r: Rect, rot: 0 | 90 | 180 | 270 = 0): Rect {
  let q = r
  for (let k = 0; k < rot / 90; k++) q = { x: 12 - q.y - q.h, y: q.x, w: q.h, h: q.w }
  return q
}

/** a home tile's footprints on the floor, in px */
export function tileBlocks(t: HomeTile): Rect[] {
  const [ox, oy] = cellPx(t.at)
  return HOME_BLOCKS[t.kind].map((r) => turn(r, t.rot)).map((r) => ({ x: ox + r.x, y: oy + r.y, w: r.w, h: r.h }))
}
```

Code in `kit/floor.ts`: signature `floorPlan(home: Home, w: number, floor: FloorHome = { tiles: [] })` (import `type Home as FloorHome, tileBlocks` from `./home`); `blocks` returns `[..., ...floor.tiles.flatMap(tileBlocks)]`.
Done when: `bun test test/floor.test.ts` green. Commit: "office: home tiles are blocks on the sim's floor, offset by their cell".

## A6. The street connects: anchors and cross-floor routes

Test first, append to `test/floor.test.ts`:

```ts
import { cellPath } from "../kit/home"
describe("the street", () => {
  const home = { tiles: [...Array.from({ length: 50 }, (_, i) => ({ kind: "street" as const, at: [i, OFFICE_ROWS] as [number, number] })), { kind: "living" as const, at: [1, OFFICE_ROWS + 1] as [number, number] }] }
  test("cellPath: BFS across a connected set of cells, start and end included", () => {
    expect(cellPath(home.tiles, [3, OFFICE_ROWS], [1, OFFICE_ROWS + 1])).toEqual([[3, OFFICE_ROWS], [2, OFFICE_ROWS], [1, OFFICE_ROWS], [1, OFFICE_ROWS + 1]])
    expect(cellPath(home.tiles, [0, 0], [1, OFFICE_ROWS + 1])).toEqual([]) // not on the floor
  })
  test("the plan exposes the street's two doors", () => {
    const p = floorPlan(DEFAULT_OFFICE, 696, home)
    const [lx, ly] = cellPx([1, OFFICE_ROWS + 1])
    expect(p.doors!.office).toEqual({ x: 696 - 18, y: OFFICE_H + CELL / 2 })
    expect(p.doors!.home).toEqual({ x: lx, y: ly })
    expect(floorPlan(DEFAULT_OFFICE, 696).doors).toBeUndefined() // no home, no street
  })
  test("walkTo: office door → street → home door, and it hits no block", () => {
    const p = floorPlan(DEFAULT_OFFICE, 696, home), l = p.layout(viewOf(office(3), 1)), blocks = p.blocks(l)
    const pts = p.walk!(p.doors!.office, p.doors!.home)
    expect(pts[0]).toEqual(p.doors!.office)
    expect(pts.at(-1)).toEqual(p.doors!.home)
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1]!, b = pts[i]!
      for (let s = 0; s <= 20; s++) {
        const x = a.x + ((b.x - a.x) * s) / 20, y = a.y + ((b.y - a.y) * s) / 20
        expect(blocks.find((r) => x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h)).toBeUndefined()
      }
    }
  })
})
```

Code:
- `kit/home.ts`: `cellPath(tiles, from, to): Pt[]` — BFS over cells in `tiles` (`neighbors`/`posKey` exist), returns the cell chain including both ends, `[]` if either is off the floor or unreachable. All doors are open this step, so open edges = adjacency.
- `kit/floor.ts`: add to the returned plan type `doors?: { office: Pt; home: Pt }` (px, `{x,y}` like `Spot` coords) and `walk?(from: Pt, to: Pt): Pt[]`. Only when the floor has a `street` tile under the door and a `living` tile: `office` = `{x: w-18, y: OFFICE_H + CELL/2}` (the street row's mid-height under the office door; requires a street tile at col `floor((w-18)/CELL)`), `home` = the first `living` tile's `cellPx` (its top-left, i.e. the lane x=0,y=0 corner: `x: lx, y: ly`). `walk`: cells = `cellPath` from the street cell under `doors.office` to the living cell; waypoints = `from`, then for each cell step the px point on the tile's left lane (`cellPx(cell)` + [0,0]) except the street row which uses `from.y`/the street mid-height line, then `to`. Keep it ≤ 25 lines; the test above is the spec (straight segments on lane x=0 and the street mid-line, so no HOME_BLOCKS rect is crossed).
Both fields are optional on the plan type, so the sim's `Plan` is unchanged this part.
Done when: `bun test test/floor.test.ts` green. Commit: "office: the street — door anchors and a walk between the office and the home".

## A7. `WideRoom.setHome` rebuilds the plan; build mode respects the office

Tests first.
In `test/wide.test.ts`:

```ts
  test("setHome gives the sim the home's blocks; the existing route walkers still pass on the composed floor", () => {
    const room = new WideRoom(696), home: Home = { tiles: [{ kind: "street", at: [0, OFFICE_ROWS] }, { kind: "living", at: [0, OFFICE_ROWS + 1] }] }
    const before = (room as unknown as { plan: { blocks: (l: unknown) => unknown[] } }).plan
    room.setHome(home)
    const after = (room as unknown as { plan: { blocks: (l: unknown) => unknown[] } }).plan
    expect(after).not.toBe(before)
    room.setHome(home) // same home: not rebuilt
    expect((room as unknown as { plan: unknown }).plan).toBe(after)
  })
```

and extend the existing route-walker tests (the "every route between every spot through every block" one, ~l.300–330) to also run with `floorPlan(DEFAULT_OFFICE, w, HOME)` where `HOME` has the street + living — use a shared `const HOME` at file top. They must pass unchanged otherwise.
In `test/home.test.ts`:

```ts
test("build mode refuses a drop overlapping the office block, and the cursor starts below it", () => {
  const b0 = startBuild({ tiles: [] }, OFFICE_ROWS)
  expect(b0.cursor).toEqual([0, OFFICE_ROWS])
  const own = place(b0)
  expect(own.home.tiles.length).toBe(1) // row OFFICE_ROWS is fine
  const up = move(own, 0, -1)
  expect(place(up).refused).toBe(true)
  const carrying = pickUp(own)
  expect(drop(move(carrying, 0, -1)).refused).toBe(true)
  expect(startBuild({ tiles: [] }).cursor).toEqual([0, 0]) // default top 0: old behaviour
})
test("gridWindow includes the office's last row as a margin for a home below it", () => {
  const w = gridWindow({ tiles: [{ kind: "street", at: [0, OFFICE_ROWS] }] }, [0, OFFICE_ROWS])
  expect(w.y0).toBe(OFFICE_ROWS - 1)
})
```

Code:
- `kit/home.ts`: `Build` gains `top: number`; `startBuild(home, top = 0)` -> `cursor: [0, top]`, `top`; `canPlace(home, tile, top = 0)` first line `if (tile.at[1] < top) return false`; `drop`/`place` pass `b.top`. Nothing else changes (`remove`, `rotate`, `undo` unaffected).
- `rooms/wide.ts` `setHome(h)`: `if (h === this.home) return; this.home = h; this.plan = floorPlan(DEFAULT_OFFICE, this.width, h)` (import `floorPlan` — already imported — and `DEFAULT_OFFICE`). Note `loadFloor()` returns a new object each call; `main.ts`'s live re-read calls `setHome` on each leave of build mode, which is fine (plan rebuild is cheap and rare). Compare by JSON string if the identity check proves too chatty: `JSON.stringify(h) === JSON.stringify(this.home)`.
- `kit/homeart.ts` `renderHome`: add `top = 0` to `HomeView`; for cells with `y < top` paint `ROLE.ground` (not the raised empty-cell colour) — the office reads as "not yours to build on". Test (append to `test/homeart.test.ts`): a view with `top: OFFICE_ROWS` has a different pixel in the office cell than an empty cell below it.
- `tui/main.ts` l.~1579: `if (!build) { const h = loadFloor(); build = startBuild(h.tiles.length ? h : defaultHome(Math.ceil(g.floorW / CELL)), OFFICE_ROWS) }`; pass `top: build.top` into the `renderHome` call at l.~2148. (`g` is the geometry variable used at l.2100; if it is not in scope at 1579, use the `viewport`/last known `floorW`.)

Done when: `mise run office:check` green (unsandboxed; it runs hours 03 and 15). Then the live check (drive-office skill): scratch `TLON_HOME` with a street+living home, press `b`... (build), see the office cells dimmed, drop refused above row `OFFICE_ROWS`; leave build mode, pan down (arrows/drag) to the street, read the header and screen text back. Paste the screen text in the PR.
Commit: "office: build mode keeps off the office; the sim re-plans when the home changes". Update `office/AGENTS.md` (floor, `loadFloor`, `OFFICE_ROWS`) in this same commit.

---

# PART (b) — the walk (branch from (a) on main)

## B1. Parse `clock_out` / `clock_in`

Test first, append to `test/home.test.ts`:

```ts
import { parseClock, loadClock } from "../tui/home"
test("parseClock: HH:MM local, anything else is ignored", () => {
  expect(parseClock("18:00")).toEqual({ h: 18, m: 0 })
  expect(parseClock("9:05")).toEqual({ h: 9, m: 5 })
  for (const bad of ["25:00", "18:60", "6pm", "", undefined, 18, null, "18:00:00"]) expect(parseClock(bad)).toBeNull()
})
test("loadClock reads clock_out and clock_in live from home.json; absent or malformed → null each", () => {
  const path = `${process.env.TMPDIR ?? "/tmp"}/clock-${Date.now()}.json`
  writeFileSync(path, JSON.stringify({ tiles: [], clock_out: "18:00", clock_in: "nope" }))
  expect(loadClock(path)).toEqual({ out: { h: 18, m: 0 }, in: null })
})
```

Code in `tui/home.ts`:

```ts
export type Clock = { h: number; m: number }
export function parseClock(v: unknown): Clock | null {
  const m = typeof v === "string" ? /^(\d{1,2}):(\d{2})$/.exec(v) : null
  if (!m) return null
  const h = Number(m[1]), min = Number(m[2])
  return h < 24 && min < 60 ? { h, m: min } : null
}
export function loadClock(path: string = HOME_PATH): { out: Clock | null; in: Clock | null } {
  try { const j = JSON.parse(readFileSync(path, "utf8")); return { out: parseClock(j?.clock_out), in: parseClock(j?.clock_in) } }
  catch { return { out: null, in: null } }
}
```

`saveHome` already spreads `...home`; extend `unknown`-safe: make it keep `clock_out`/`clock_in` from the file when saving (read the file, copy those two keys) — add a test: save after load keeps the clock keys. Done when `bun test test/home.test.ts` green. Commit: "office: home.json clock_out / clock_in".

## B2. The pure "where should you be" brain — `kit/whereabouts.ts` (new)

One small pure module so keys, clock and attention are all unit-tested without the TUI.

Test first, `test/whereabouts.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { LOCK_MS, attention, atClock, choose, type Side } from "../kit/whereabouts"

describe("whereabouts", () => {
  const out = { h: 18, m: 0 }, back = { h: 9, m: 0 }
  test("atClock: 18:00 sends you home, 09:00 back, any other minute nothing", () => {
    expect(atClock(new Date(2026, 9, 5, 18, 0), { out, in: back })).toBe("home")
    expect(atClock(new Date(2026, 9, 5, 9, 0), { out, in: back })).toBe("office")
    expect(atClock(new Date(2026, 9, 5, 12, 0), { out, in: back })).toBeNull()
    expect(atClock(new Date(2026, 9, 5, 18, 0), { out: null, in: null })).toBeNull()
  })
  test("attention maps events to a side", () => {
    expect(["thread", "terminal", "lazygit"].map((e) => attention(e))).toEqual(["office", "office", "office"])
    expect(["routine", "life"].map((e) => attention(e))).toEqual(["home", "home"])
    expect(attention("something-else")).toBeNull()
  })
  test("an explicit key or clock event wins over attention for 60 s, then attention is heard again", () => {
    let s = { side: "office" as Side, lockUntil: 0 }
    s = choose(s, { kind: "key", to: "home" }, 1_000)
    expect(s.side).toBe("home")
    s = choose(s, { kind: "attention", to: "office" }, 1_000 + LOCK_MS - 1)
    expect(s.side).toBe("home")
    s = choose(s, { kind: "attention", to: "office" }, 1_000 + LOCK_MS)
    expect(s.side).toBe("office")
  })
  test("a clock event is explicit too; a second explicit one always wins", () => {
    let s = { side: "office" as Side, lockUntil: 0 }
    s = choose(s, { kind: "clock", to: "home" }, 0)
    s = choose(s, { kind: "key", to: "office" }, 10)
    expect(s.side).toBe("office")
  })
})
```

Code:

```ts
import type { Clock } from "../tui/home"
export type Side = "home" | "office"
export const LOCK_MS = 60_000
export type State = { side: Side; lockUntil: number }
export type Cause = { kind: "key" | "clock" | "attention"; to: Side }

export function atClock(now: Date, c: { out: Clock | null; in: Clock | null }): Side | null {
  const at = (k: Clock | null) => k !== null && k.h === now.getHours() && k.m === now.getMinutes()
  return at(c.out) ? "home" : at(c.in) ? "office" : null
}
const HOME_EVENTS = new Set(["routine", "life"]), OFFICE_EVENTS = new Set(["thread", "terminal", "lazygit"])
export function attention(event: string): Side | null { return HOME_EVENTS.has(event) ? "home" : OFFICE_EVENTS.has(event) ? "office" : null }

export function choose(s: State, c: Cause, now: number): State {
  if (c.kind !== "attention") return { side: c.to, lockUntil: now + LOCK_MS }
  return now < s.lockUntil ? s : { side: c.to, lockUntil: s.lockUntil }
}
```

(`kit/` importing a type from `tui/` is a layer reach — move `Clock` to `kit/home.ts` and have `tui/home.ts` import it.) The caller must fire `atClock` once per matching minute (guard in B7 with a "last fired minute" key). Done when: `bun test test/whereabouts.test.ts` green. Commit: "office: whereabouts — clock, attention and the 60 s lock, pure".

## B3. The operator actor in the sim

Before coding read `kit/sim.ts` `Actor` / `Errand` types and how `step` moves actors along `path` (the `d.path`, `goalOf`, `inRoom` logic in `rooms/wide.ts` ~l.200–260); the figure reuses actor movement, it does not invent a second mover.

Test first, `test/operator.test.ts`:

```ts
describe("the operator figure", () => {
  const home = { tiles: [...street50, living] }          // the same fixture as test/floor.test.ts (export it from there)
  test("at the office she sits at the boss desk; home is `office`", () => {
    const room = new WideRoom(696); room.setHome(home); step(room, 50)
    expect(room.you()).toMatchObject({ where: "office" })
  })
  test("go('home') walks: `walking` mid-way, `home` after, standing in the living tile", () => {
    const room = new WideRoom(696); room.setHome(home); room.go("home")
    step(room, 5); expect(room.you().where).toBe("walking")
    step(room, 3000); expect(room.you().where).toBe("home")
    const [lx, ly] = cellPx([1, OFFICE_ROWS + 1]); expect(near(room.you(), lx, ly, 14)).toBe(true)
  })
  test("fast-walk is ~4x faster over the same path", () => { /* go('home', {fast:true}) arrives in <= 1/3 the ticks */ })
  test("with no street/home the walk is refused: go() returns false and she stays", () => {})
  test("the office keeps running while you are home (desks stay staffed)", () => {})
})
```

Fill the elided bodies with the same shape as above before committing (each is 3–6 lines against the room's public API).

Code (decisions fixed, internals for the builder):
- `kit/sim.ts` (or the `WideRoom` subclass if `sim.ts` is generic — the plan's `walk`/`doors` live on the wide plan only, so put the figure in `rooms/wide.ts` unless a sim hook is needed): an `operator` actor `{ name: "you", look: operatorLook, x,y, path, where }`. `where: "office"|"home"|"walking"`.
- `go(side, {fast}?)`: `false` if `plan.doors` is absent; otherwise `path = plan.walk(...)` from the figure's spot: desk -> hallway row -> `plan.door` (reuse `plan.route(x, from, plan.door)`), then `doors.office` -> `walk` -> `doors.home`; the figure's step length is `1` normal, `4` with `fast`. Home -> office reverses it.
- Home spot = `bed` tile if present else `living` tile's cell; office spot = `yourDesk(a)`.
- `render`: draw with the operator's look from `kit/looks.ts` (find the operator's look key there — Uqbar/boss desk uses `plan.layout(a).desks.find(x => x.kind === "boss")`), and push a `Hit` so she is clickable like any actor (copy one actor's hit push).
- `inRoom` clamps y to `WIDE_H - 12`; the figure's path must not go through `inRoom` (floor is taller) — clamp to `height` for her only.
- `WideRoom.you(): { where: ...; x: number; y: number }` for the TUI and tests.
Done when: `bun test test/operator.test.ts test/wide.test.ts` green (golden unchanged: the figure is only drawn when `setHome` has a street, else it stays hidden at the desk exactly as the office is drawn today — **the golden must not move**; if drawing her at the desk moves it, draw her only when `plan.doors` exists). Commit: "office: the operator's figure on the floor, and the walk between desk and living tile".

## B4. The viewport follows the walk

Test first, append to `test/viewport.test.ts`:

```ts
test("followWalk re-centres on the figure each frame until she has arrived, then lets go", () => {
  const v = { x: 0, y: 0, w: 100, h: 60 }
  const a = followWalk(v, { where: "walking", x: 300, y: 250 }, 696, 300)
  expect(a.y).toBeGreaterThan(0)
  const done = followWalk(a, { where: "home", x: 300, y: 250 }, 696, 300)
  expect(done).toBe(a)
})
test("jumpTo puts the destination in view at once", () => { /* centerViewport on the door-home point, clamped */ })
```

Code in `tui/viewport.ts`: `followWalk(v, you, floorW, floorH) = you.where === "walking" ? centerViewport(v, you.x, you.y, floorW, floorH) : v`; `jumpTo` is `centerViewport` with the destination — reuse, add only a test. Done when `bun test test/viewport.test.ts` green. Commit: "office: the viewport follows the walk".

## B5. Route test: the real walk hits no block (spec check)

Test (in `test/operator.test.ts`): sample the figure's position every tick during `go("home")` and assert it is never inside `plan.blocks(...)` (reuse the sampling walker from `test/wide.test.ts`: factor it into `test/walk.ts` as `insideAny(blocks, x, y)` and import it in both — the one DRY refactor allowed). Assert the visited path passes `doors.office` then a street-row point (`y ≈ OFFICE_H + CELL/2`) then `doors.home`. Code: nothing unless it fails (then fix the B3 path). Commit: "test: the operator's walk crosses the street and hits no block".

## B6. The keys: `h` home, `o` office

Test first (existing `test/keys.test.ts` pattern; read it for how scopes and clashes are asserted):

```ts
test("h and o walk you home / to the office in the room, and stay the hiring hall / notes in the home card", () => {
  expect(KEYS.find((k) => k.id === "room.home")).toMatchObject({ scope: "room", key: "h" })
  expect(KEYS.find((k) => k.id === "room.office")).toMatchObject({ scope: "room", key: "o" })
  expect(KEYS.find((k) => k.id === "home.h")!.scope).toBe("card:home")
})
```

plus the existing "no two bindings clash in a scope" test must stay green (if `LEGEND_CHARS`, line 21, is a fixed list of legend letters the help line shows, add them only if the scope shows there).
Code: two entries in `tui/keys.ts` (`room` scope — find the scope name the other room-level keys use in that file and use it exactly); in `tui/main.ts`, the dispatch for them calls `go("home", { fast: true })` / `go("office", { fast: true })` on the room (`room0 instanceof WideRoom`), `choose(whereabouts, {kind:"key", to}, Date.now())`, and `viewport = jumpTo(...)`. If `h`/`o` are bound earlier in the main-loop switch (`case "o": return open({ kind: "notes" })`, l.2457) check that case is inside the home card's handler only; if it is global, scope it to the card first (own commit) — otherwise the room key is shadowed. Done when `bun test test/keys.test.ts` green. Commit: "office: h and o walk you home and to the office".

## B7. The clock and the attention hooks in `main.ts`

Tests are B2's (pure). Wiring (no new pure code): keep `let where: State = { side: "office", lockUntil: 0 }` and `let lastClockMinute = ""` in `main.ts`; in the existing per-tick/frame timer call:

```ts
const now = new Date(), key = `${now.getHours()}:${now.getMinutes()}`
const due = key !== lastClockMinute ? atClock(now, loadClock()) : null   // loadClock() re-reads home.json live
lastClockMinute = key
if (due) apply(choose(where, { kind: "clock", to: due }, Date.now()))
```

and `apply(next)`: if `next.side !== where.side`, `room.go(next.side)` (normal speed for clock/attention, fast for keys), then `where = next`. Call `attention("thread")` where a thread card/terminal/lazygit opens (find the three `open(...)` / terminal-zoom sites: grep `kind: "thread"`, the terminal zoom, the lazygit pane), and `attention("routine")` / `attention("life")` where a routine is stamped / the `L` life card opens. Each is one line: `apply(choose(where, { kind: "attention", to }, Date.now()))`. Done when `bun run typecheck` and the full `bun test` pass. Commit: "office: the clock and attention move you between home and the office".

## B8. Coworkers cross (consult / nag)

Test first, `test/operator.test.ts`: a `Visit`-style consult for a coworker while `you().where === "home"` sets that coworker's goal to `plan.doors.home`, and they arrive there (reuse `plan.walk`); while you are at the office nothing changes (existing visit tests unchanged). Code: in `rooms/wide.ts` where `visit(h)` / the consult walk resolves its target (`this.plan.visit(host)`, l.~375, 401, 701): if the operator is home, the target spot is `doors.home` (routed with `plan.route` to the office door then `plan.walk`). No doorbell (#32 holds). Done when `bun test` green. Commit: "office: a coworker with something for you crosses the street".

## Part (b) done when

- `mise run office:check` green (unsandboxed); `wcag.test.ts` passes (run it explicitly; it takes the viewport position from the test, so check the new taller floor at each position).
- **The walk is seen** — `drive-office` session on a scratch `TLON_HOME` with a street+living home: press `h`, read the screen mid-walk (figure on the street row, viewport moved) and after (figure in the living tile); press `o` back; set `clock_out` to now+1 min and watch it leave. Screen text pasted in the PR.
- `office/AGENTS.md` updated in the same commits (keys `h`/`o`, `clock_out`/`clock_in`, the figure, `kit/whereabouts.ts`).

## Risks to watch

- The golden hash moving: the figure (B3) and floor (A3) must draw nothing without a home. Check `bun test test/wide.test.ts` after every task.
- `h`/`o` key shadowing (B6) — read `tui/main.ts` ~l.2457 first.
- B3 is the biggest task: if the builder finds it spans more than `rooms/wide.ts` + one test file, split it into "figure at desk" and "go()/walk".
- `homeNow` being re-read live on leaving build mode creates a new `Home` object each time; `setHome` must not rebuild the plan needlessly (A7 note).
