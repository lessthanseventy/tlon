# Plan — home-tile renderer (ticket #45, thread 187)

Spec: `spec.md`. All paths relative to the worktree root. Elixir untouched. Run office tests with
`cd office && bun test test/homeart.test.ts`; gate is `mise run office:check` then `mise run check`
(run unsandboxed). One commit per task, trailer `Co-Authored-By: <your model> …` per AGENTS.md.

Decisions fixed here (so nobody re-litigates): tile = 12×12 px sprite in a 14-px cell (1-px margin);
build mode shows the pixel home as the **full room image** (spec's recommendation); **no text ink,
no hits** this step (cell clicks are a later add — drop that line of the spec); the hook is the plain
exported record `TILE_ART` (YAGNI: no register function); sprites are `.`-clear strings blitted over a
floor fill, colours from `ROLE` at draw time.

## Task 1 — `rotated()` sprite helper
Files: new `office/kit/homeart.ts`, new `office/test/homeart.test.ts`.

Test first (`office/test/homeart.test.ts`):
```ts
import { describe, expect, test } from "bun:test"
import { rotated } from "../kit/homeart"

describe("rotated", () => {
  const s = ["abc", "def", "ghi"]
  test("clockwise quarter turns", () => {
    expect(rotated(s, 0)).toEqual(s)
    expect(rotated(s, 90)).toEqual(["gda", "heb", "ifc"])
    expect(rotated(s, 180)).toEqual(["ihg", "fed", "cba"])
    expect(rotated(s, 270)).toEqual(["cfi", "beh", "adg"])
  })
})
```
Run → red (no module). Implement `office/kit/homeart.ts`:
```ts
// Home tiles as pixel art: `TILE_ART` maps a tile kind to the function that paints it, and
// `renderHome` lays the build grid out as a Frame. A new tile kind plugs in by adding a key.
import { Canvas, type Frame } from "./canvas"
import { gridWindow, type Home, type HomeTile, type Pt } from "./home"
import { ROLE, tint } from "./palette"

export const TILE = 12
const CELL = TILE + 2

/** a square sprite turned clockwise by `rot` degrees */
export function rotated(rows: string[], rot: 0 | 90 | 180 | 270 = 0): string[] {
  let r = rows
  for (let q = 0; q < rot / 90; q++) r = r.map((_, j) => r.map((_, i) => r[r.length - 1 - i]![j]!).join(""))
  return r
}
```
Done: test green. Commit "office: rotated() — a sprite turned in quarter turns".

## Task 2 — sprites, `TILE_ART`, fallback
Files: `office/kit/homeart.ts`, `office/test/homeart.test.ts`.

Tests (append):
```ts
import { Canvas } from "../kit/canvas"
import { CATALOGUE, type HomeTile } from "../kit/home"
import { SPRITES, TILE, TILE_ART, paintTile } from "../kit/homeart"

const paint = (t: HomeTile) => { const c = new Canvas(TILE, TILE); paintTile(c, 0, 0, t); return Buffer.from(c.rgba).toString("hex") }

describe("sprites", () => {
  test("every catalogue kind has a TILE×TILE sprite", () => {
    for (const k of CATALOGUE) {
      expect(SPRITES[k]!.length).toBe(TILE)
      for (const row of SPRITES[k]!) expect(row.length).toBe(TILE)
    }
  })
  test("kinds look different from each other, and a rotated tile from its upright self", () => {
    const looks = CATALOGUE.map((kind) => paint({ kind, at: [0, 0] }))
    expect(new Set(looks).size).toBe(CATALOGUE.length)
    for (const kind of CATALOGUE) expect(paint({ kind, at: [0, 0], rot: 90 })).not.toBe(paint({ kind, at: [0, 0] }))
  })
  test("a kind with no art still draws (plain tile), and the hook takes over once registered", () => {
    const garden = { kind: "garden", at: [0, 0] } as unknown as HomeTile
    const plain = paint(garden)
    expect(plain).not.toBe(paint({ kind: "living", at: [0, 0] }))
    let called = 0
    TILE_ART.garden = (c, x, y) => { called++; c.px(x, y, TILE, TILE, "#112233") }
    try { expect(paint(garden)).not.toBe(plain); expect(called).toBe(1) } finally { delete TILE_ART.garden }
  })
})
```
Implement (append to `homeart.ts`):
```ts
export type TileArt = (c: Canvas, x: number, y: number, tile: HomeTile) => void

/** '.' is clear (the floor shows). Colours per letter come from `PALETTES`, read at draw time. */
export const SPRITES: Record<string, string[]> = {
  living: ["............", ".rrrrrrrrrr.", ".rrrrrrrrrr.", ".rrrrrrrrrr.", ".rrrrrrrrrr.", "............",
           ".cccccccccc.", ".cccccccccc.", ".cccccccccc.", ".ccc....ccc.", "............", "...........l"],
  kitchen: ["wwwwwwwwwwww", "wssw..oo.www", "............", "............", "...tttttt...", "...tttttt...",
            "...tttttt...", "............", "............", "............", "............", "...........k"],
  bathroom: ["............", ".bbbb.......", ".bbbb.....ss", ".bbbb.....ss", ".bbbb.......", ".bbbb.......",
             "............", "............", "..pp........", "..pp........", "............", "...........m"],
  bedroom: ["............", ".pppppp.....", ".pppppp.nn..", ".qqqqqq.nn..", ".qqqqqq.....", ".qqqqqq.....",
            ".qqqqqq.....", ".qqqqqq.....", ".qqqqqq.....", "............", "............", "............"],
  street: ["kkkkkkkkkkkk", "kkkkkkkkkkkk", "eeeeeeeeeeee", "eeeeeeeeeeee", "eeeeeeeeeeee", "ddeeddeeddee",
           "eeeeeeeeeeee", "eeeeeeeeeeee", "eeeeeeeeeeee", "kkkkkkkkkkkk", "kkkkkkkkkkkk", "kkkkkkkkkkkk"],
}

const floor = () => tint(ROLE.structure, ROLE.ground, 0.3)
const PALETTES = (): Record<string, Record<string, string>> => ({
  living: { r: tint(ROLE.attention, ROLE.ground, 0.5), c: ROLE.assistant, l: ROLE.body },
  kitchen: { w: ROLE.inactive, s: ROLE.key, o: ROLE.alarm, t: ROLE.structure, k: ROLE.body },
  bathroom: { b: tint(ROLE.key, ROLE.ground, 0.6), s: ROLE.key, p: ROLE.prose, m: ROLE.body },
  bedroom: { p: ROLE.prose, q: ROLE.planner, n: ROLE.structure },
  street: { k: ROLE.borderInactive, e: ROLE.edge, d: ROLE.prose },
})

/** kind → how to paint it. A kind absent here falls back to `plainTile`; later work adds its key. */
export const TILE_ART: Record<string, TileArt> = Object.fromEntries(
  Object.keys(SPRITES).map((kind): [string, TileArt] => [kind, (c, x, y, t) => {
    c.px(x, y, TILE, TILE, floor())
    c.blit(rotated(SPRITES[kind]!, t.rot ?? 0), x, y, PALETTES()[kind]!)
  }]),
)

/** a kind with no art: a floor square with a border, so the tile is still there to see and move */
const plainTile: TileArt = (c, x, y) => {
  c.px(x, y, TILE, TILE, ROLE.meta)
  c.px(x + 1, y + 1, TILE - 2, TILE - 2, floor())
}

export function paintTile(c: Canvas, x: number, y: number, t: HomeTile) {
  (TILE_ART[t.kind] ?? plainTile)(c, x, y, t)
}
```
Verify: `bun test test/homeart.test.ts` green (if sprite row lengths fail, fix the offending string —
every row is exactly 12 chars). Commit "office: home tile sprites and the TILE_ART hook".

## Task 3 — `renderHome`
Files: `office/kit/homeart.ts`, `office/test/homeart.test.ts`.

Tests (append):
```ts
import { renderHome } from "../kit/homeart"
import { ROLE } from "../kit/palette"

const home = { tiles: [{ kind: "living", at: [0, 0] }, { kind: "street", at: [1, 0] }] } as const
const base = { home: home as never, cursor: [0, 0] as [number, number], carrying: null, refused: false, w: 200, h: 100 }

describe("renderHome", () => {
  test("a frame of the size asked, one bracket on the cursor", () => {
    const f = renderHome(base)
    expect([f.width, f.height, f.rgba.length]).toEqual([200, 100, 200 * 100 * 4])
    const b = f.ink.filter((i) => i.t === "brackets")
    expect(b.length).toBe(1)
    expect(b[0]).toMatchObject({ color: ROLE.attention })
  })
  test("a refused drop turns the cursor alarm-coloured", () => {
    expect(renderHome({ ...base, refused: true }).ink.find((i) => i.t === "brackets")).toMatchObject({ color: ROLE.alarm })
  })
  test("a carried tile shows at the cursor, dimmed against the same tile placed", () => {
    const empty = { tiles: [{ kind: "street", at: [1, 0] }] } as never
    const carrying = { kind: "living", at: [0, 0] } as never
    const hold = renderHome({ ...base, home: empty, carrying })
    const placed = renderHome({ ...base, home: { tiles: [carrying, { kind: "street", at: [1, 0] }] } as never })
    expect(Buffer.from(hold.rgba).equals(Buffer.from(placed.rgba))).toBe(false)
    expect(hold.rgba.some((v, i) => v !== 0 && i % 4 === 3)).toBe(true) // it painted something
  })
})
```
Implement (append):
```ts
export type HomeView = { home: Home; cursor: Pt; carrying: HomeTile | null; refused: boolean; w: number; h: number }

/** the build grid as a Frame of w×h logical px: every cell of `gridWindow`, centred; no text, no hits */
export function renderHome({ home, cursor, carrying, refused, w, h }: HomeView): Frame {
  const c = new Canvas(w, h)
  c.px(0, 0, w, h, ROLE.ground)
  const win = gridWindow(home, cursor)
  const ox = Math.floor((w - (win.x1 - win.x0 + 1) * CELL) / 2), oy = Math.floor((h - (win.y1 - win.y0 + 1) * CELL) / 2)
  const pos = ([x, y]: Pt): Pt => [ox + (x - win.x0) * CELL + 1, oy + (y - win.y0) * CELL + 1]
  for (let y = win.y0; y <= win.y1; y++) for (let x = win.x0; x <= win.x1; x++) {
    const [px, py] = pos([x, y])
    const t = home.tiles.find((h) => h.at[0] === x && h.at[1] === y)
    if (t) paintTile(c, px, py, t)
    else c.px(px, py, TILE, TILE, ROLE.raised)
  }
  const [cx, cy] = pos(cursor)
  if (carrying) {
    paintTile(c, cx, cy, { ...carrying, at: cursor })
    c.glow(cx, cy, TILE, TILE, ROLE.ground, 0.45)
  }
  return { rgba: c.rgba, width: w, height: h, hits: [],
    ink: [{ t: "brackets", x: cx - 1, y: cy - 1, w: TILE + 2, h: TILE + 2, color: refused ? ROLE.alarm : ROLE.attention }] }
}
```
(Shadowed `h` in the `find` callback is harmless but rename it `q` if the typecheck complains.)
Verify: tests green + `cd office && bunx tsc --noEmit` (or `mise run office:check`). Commit
"office: renderHome — the build grid as a Frame".

## Task 4 — wire into build mode
Files: `office/tui/main.ts` only.

No unit seam here (it is the render loop); the check is the drive in Task 5. Edits in `draw()`
(~line 1238, the `// the room` block) and the build `esc` action (~line 944):

1. Replace the frame/seen lines with:
```ts
  const room0 = room()
  const building = mode.kind === "build" && build !== null
  const fresh = !frame
  const vp = building ? { x: 0, y: 0, w: viewport.w, h: viewport.h } : viewport
  if (building) {
    frame = renderHome({ home: build!.home, cursor: build!.cursor, carrying: build!.carrying, refused: build!.refused, w: Math.ceil(vp.w), h: Math.ceil(vp.h) })
    imageDirty = true
  } else if (fresh || roomChanged) { frame = room0.render(...unchanged args...); roomChanged = false }
  const seen = clipFrame(frame!, vp)
```
and in the next two lines pass `vp` instead of `viewport` to `kittyImage(seen, g, vp)` and `textLayer(seen, g, vp)`.
Add `import { renderHome } from "../kit/homeart"` beside the `../kit/home` import (line 14).
2. Build mode's `esc` action: `back(true); roomChanged = true; draw()` → `back(true); changed(); draw()`
   (`changed()` also sets `imageDirty`, so the room image is re-sent).
3. In the `case "build"` card, delete the `code`/`rows` text grid (the `for y … for x …` loop and `code`),
   leaving `rows` as a single `{ segs: [dim("the home is drawn above")] }`; keep `title` and all `actions`.
   Remove `gridWindow`/`HomeTile` from the `../kit/home` import only if now unused (typecheck says).
Verify: `mise run office:check` green (typecheck + all tests incl. `wcag`, `golden` — golden must NOT
change; if it does, you touched the room path, revert that). Commit "office: build mode draws the home as pixel art".

## Task 5 — docs, drive, gate, report
1. `office/AGENTS.md`: in the `kit/` list add after `furniture.ts`: "the home's tiles as pixel art
   (`homeart.ts`: `TILE_ART`, kind → painter, a missing kind draws plain; `renderHome` the build grid as a Frame)".
2. Drive per the `drive-office` skill (private tmux; never the operator's terminal): start the TUI with
   `TLON_HOME=$TMPDIR/home.json`, press `B`, then `n` ×3 (cycle kinds), `right`, `n`, `r` (rotate),
   `enter` pick up / move / `enter` drop, `esc`. Confirm each kind shows a distinct sprite, rotation turns it, a
   split-making drop shows alarm brackets, and `esc` restores the room. PNG-proxy or half-block capture is fine; attach one.
3. `mise run office:check` then `mise run check` (unsandboxed). Both green.
4. Commit docs ("office: AGENTS.md names homeart"). In the review submission say: the hook is `TILE_ART`
   in `office/kit/homeart.ts`; #176 garden / #185 street+mailbox / #172 weather / #40 may be released and
   each adds `TILE_ART.<kind>` (+ catalogue entry in `kit/home.ts`).

## Out of scope
Mailbox, weather, errands, garden art, cell hits/clicks, text labels, desktop surface, server.
