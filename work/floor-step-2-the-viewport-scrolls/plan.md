# Floor step 2: the viewport scrolls — plan

9 bite-sized tasks, each its own commit, TDD (failing test first). All paths relative to repo
root. Office suite: `mise run office:watch` while iterating, or `cd office && bun test <file>` for
one file; `mise run office:check` is the gate. Tasks 1–4 have no dependencies on each other and
can be built/committed in any order; 5–9 depend on 2 and 4.

## 1. shift-arrow keys — `office/tui/term.ts`

Failing test first, `office/test/term.test.ts` (new file):
```ts
import { describe, expect, test } from "bun:test"
import { tokenize } from "../tui/term"

describe("shift+arrow keys", () => {
  test("xterm SGR shift-modified arrows tokenize to shift-up/down/left/right", () => {
    expect(tokenize("\x1b[1;2A").inputs).toEqual([{ t: "key", key: "shift-up" }])
    expect(tokenize("\x1b[1;2B").inputs).toEqual([{ t: "key", key: "shift-down" }])
    expect(tokenize("\x1b[1;2C").inputs).toEqual([{ t: "key", key: "shift-right" }])
    expect(tokenize("\x1b[1;2D").inputs).toEqual([{ t: "key", key: "shift-left" }])
  })
})
```
Fix: add to the `KEYS` table (term.ts:33):
```ts
"[1;2A": "shift-up", "[1;2B": "shift-down", "[1;2C": "shift-right", "[1;2D": "shift-left",
```
Done: new test green, `bun test office/test/term.test.ts` passes, existing tokenizer tests
unaffected.

## 2. `Viewport` type + clamp/pan — new `office/tui/viewport.ts`

Failing test first, `office/test/viewport.test.ts`:
```ts
import { describe, expect, test } from "bun:test"
import { clampViewport, panViewport, type Viewport } from "../tui/viewport"

describe("viewport clamp and pan", () => {
  test("pan moves by the delta", () => {
    const v: Viewport = { x: 10, y: 10, w: 100, h: 100 }
    expect(panViewport(v, 5, -3, 500, 500)).toEqual({ x: 15, y: 7, w: 100, h: 100 })
  })
  test("clamps at the floor's edges on every side", () => {
    const v: Viewport = { x: 10, y: 10, w: 100, h: 100 }
    expect(panViewport(v, -100, -100, 500, 500)).toEqual({ x: 0, y: 0, w: 100, h: 100 })
    expect(panViewport(v, 1000, 1000, 500, 500)).toEqual({ x: 400, y: 400, w: 100, h: 100 })
  })
  test("a viewport bigger than the floor centers and never reports negative room", () => {
    const v: Viewport = { x: 0, y: 0, w: 600, h: 600 }
    expect(clampViewport(v, 500, 500)).toEqual({ x: 0, y: 0, w: 600, h: 600 })
  })
})
```
Implementation:
```ts
// A viewport over a floor bigger than the terminal: a window in logical px, clamped to the
// floor's bounds, that pans on keys or a drag instead of the room ever being asked to fit.
export type Viewport = { x: number; y: number; w: number; h: number }

export function clampViewport(v: Viewport, floorW: number, floorH: number): Viewport {
  const x = v.w >= floorW ? 0 : Math.max(0, Math.min(v.x, floorW - v.w))
  const y = v.h >= floorH ? 0 : Math.max(0, Math.min(v.y, floorH - v.h))
  return { ...v, x, y }
}

export function panViewport(v: Viewport, dx: number, dy: number, floorW: number, floorH: number): Viewport {
  return clampViewport({ ...v, x: v.x + dx, y: v.y + dy }, floorW, floorH)
}

/** a viewport centred on a point, clamped to the floor */
export function centerViewport(v: Viewport, cx: number, cy: number, floorW: number, floorH: number): Viewport {
  return clampViewport({ ...v, x: cx - v.w / 2, y: cy - v.h / 2 }, floorW, floorH)
}
```
Done: `bun test office/test/viewport.test.ts` green. Pure module, no render/key wiring yet — that's
tasks 7–8.

## 3. `Sim.at(agent)` — `office/kit/sim.ts`

Failing test first, add to `office/test/sim.test.ts` (check if it exists; if not, new file),
reusing the `office()` fixture from `wcag.test.ts`:
```ts
test("Sim.at returns a seated actor's current spot, or null for a stranger", () => {
  const room = new WideRoom(696)
  room.step(viewOf(office(), 1)) // seeds actors from the roster
  const at = room.at("yu")
  expect(at === null || (typeof at.x === "number" && typeof at.y === "number")).toBe(true)
  expect(room.at("nobody-by-this-name")).toBeNull()
})
```
Implementation, inside `class Sim` (near `actors`, sim.ts:103):
```ts
/** an actor's current spot on the floor, by agent name — null if they aren't seated here */
at(agent: string): Spot | null { return this.actors.get(agent)?.spot ?? null }
```
Done: test green, `office/kit/sim.ts` has no other behavior change.

## 4. Geometry: `floorW`/`floorH` + flat `k=2` kitty legibility — `office/tui/paint.ts`

Failing test first, add to `office/test/paint.test.ts` (new, or an existing file that covers
`geometry`):
```ts
test("kitty mode uses a flat legibility scale of 2, not fit, once the floor exceeds the terminal", () => {
  const g = geometry(2000, 1000, 80, 40, 3, { w: 8, h: 18 }, true)
  expect(g.k).toBe(2)
  expect(g.floorW).toBe(2000)
  expect(g.floorH).toBe(1000)
})
test("half-block mode is unchanged: still the largest fitting scale", () => {
  const g = geometry(100, 100, 80, 40, 3, { w: 8, h: 18 }, false)
  expect(g.kitty).toBe(false)
})
```
Implementation: `Geometry` (paint.ts:12) gains `floorW: number; floorH: number`. In `geometry()`
(paint.ts:15), the kitty branch becomes:
```ts
export function geometry(W: number, H: number, termCols: number, termRows: number, below: number, cell: { w: number; h: number } | null, kitty: boolean): Geometry {
  const room = Math.max(4, termRows - below)
  if (kitty && cell) {
    const k = 2
    const cols = Math.min(termCols, Math.ceil((W * k) / cell.w)), rows = Math.min(room, Math.ceil((H * k) / cell.h))
    return { k, cw: cell.w, ch: cell.h, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: true, floorW: W, floorH: H }
  }
  const k = Math.min(termCols / W, (room * 2) / H)
  const cols = Math.floor(W * k), rows = Math.floor((H * k) / 2)
  return { k, cw: 1, ch: 2, col: Math.max(0, Math.floor((termCols - cols) / 2)), row: 0, cols, rows, kitty: false, floorW: W, floorH: H }
}
```
Note: `cols`/`rows` here are now the *viewport's* cell box (capped to the terminal), not
necessarily the whole floor — check `main.ts`/`wide.ts` for any caller that assumed
`cols === floor width in cells`; flag any found, don't silently paper over.
Done: both tests green; `office/test/wcag.test.ts`'s existing calls to `geometry()` still pass
unmodified (kitty=true there, with a small room that fits — check no test there asserts a `k`
value that this changes; if one does, that assertion moves to expect `k === 2`).

## 5. `kittyImage` source-rect crop — `office/tui/paint.ts`

Failing test, `office/test/paint.test.ts`:
```ts
test("kittyImage places the full floor once and crops via the placement's source rect", () => {
  const fr = { rgba: new Uint8Array(20 * 20 * 4), width: 20, height: 20, ink: [], hits: [] }
  const g = { k: 2, cw: 8, ch: 18, col: 0, row: 0, cols: 10, rows: 10, kitty: true, floorW: 20, floorH: 20 }
  const out = kittyImage(fr, g, { x: 4, y: 4, w: 10, h: 10 })
  expect(out).toContain("x=4,y=4,w=20,h=20") // placement crop in art px — see implementation note
})
```
Implementation note: read the kitty graphics protocol's placement spec for `a=p` with
`x=,y=,w=,h=,X=,Y=` before writing this — the existing `kittyImage` only ever sends `a=T`
transmit-and-display with no crop. This task changes it to: transmit once per frame change
(`a=t`, keep `i=1`), then a separate `a=p,i=1,x=,y=,w=,h=` placement per draw using the viewport's
rect in art px (`viewport.x * g.k` etc.), replacing today's always-`a=T`. This is the one task in
the plan where the exact escape-sequence fields need the protocol doc open, not just this plan —
if the placement crop doesn't behave as expected against a real kitty terminal, say so on the
thread rather than shipping a guess.
Done: the unit test on the escape-sequence shape is green, AND a driven look in a real
kitty-capable terminal (ghostty, `OFFICE_GRAPHICS=kitty`) shows a cropped floor panning without a
visible re-decode flash.

## 6. `textLayer` viewport crop — `office/tui/paint.ts`

Failing test, `office/test/paint.test.ts`:
```ts
test("textLayer only emits rows/cols inside the viewport", () => {
  const fr = { rgba: new Uint8Array(20 * 20 * 4).fill(255), width: 20, height: 20, ink: [], hits: [] }
  const g = { k: 1, cw: 1, ch: 2, col: 0, row: 0, cols: 20, rows: 10, kitty: false, floorW: 20, floorH: 20 }
  const rows = textLayer(fr, g, { x: 4, y: 6, w: 10, h: 10 })
  expect(rows.length).toBe(5) // 10 px tall viewport / ch=2
  expect(rows[0]!.length).toBe(10) // 10 px wide viewport / cw=1 -> 10 cells
})
```
Implementation: `textLayer` (paint.ts:130) takes a third `viewport: Viewport` param; its row/col
loops (`for (let r = 0; r < g.rows...)`, `for (let c = 0; c < g.cols...)`) iterate the viewport's
cell range instead of `0..g.rows`/`0..g.cols`, offsetting the `at()` sampling by
`viewport.x`/`viewport.y`.
Done: test green; the caller at `main.ts:920` updated to pass the current viewport.

## 7. Wire it into `main.ts` — state, `onKey`, `onMouse`

No new unit test (this is glue over tasks 2–6, already tested); the check is task 9's
`drive-office` run. Changes:
- module state: `let viewport: Viewport, follow = true` (initialised in `layoutScreen()` centred
  on the office zone — per spec.md's clarification — via `centerViewport`).
- `onKey` (main.ts:1048 switch): add cases `shift-up`/`shift-down`/`shift-left`/`shift-right` →
  `panViewport` + `follow = false`; `.` → recentre on the office zone + `follow = true`; `,` →
  resolve the first `Need` (blocking before decide) via the roster entry's `agent` → `room().at(agent)`,
  recentre — a no-op if the queue is empty or the agent can't be resolved.
- `onMouse` (main.ts:1094): on a press-and-drag (not just press) over the room, call `panViewport`
  by the drag delta and set `follow = false`. `onMouse` already sees motion events (`m.motion`);
  track "button down" across motion events to compute a drag delta — no new terminal-protocol
  plumbing needed.
- `draw()` (main.ts:919-920): pass `viewport` into `kittyImage`/`textLayer`.
Done: `mise run office:check` green; a driven look (task 9) shows panning working end to end.

## 8. `Ink`/`Hit` clipping + edge markers

Failing test, extend `office/test/paint.test.ts`:
```ts
test("a hit outside the viewport is dropped; a label outside becomes an edge marker", () => {
  // construct a Frame with one Hit at x=500 (far outside a 0..100 viewport) and assert it's
  // absent from the clipped Hit list, and that an Ink label there is replaced by a single-glyph
  // marker pointing toward it (◂ left / ▸ right / ▴ up / ▾ down).
})
```
Implementation: a new function, `clipFrame(fr: Frame, viewport: Viewport): Frame`, in `paint.ts`
(or `viewport.ts`), called once in `draw()` before `kittyImage`/`textLayer`/`hitAt`. Marker glyph:
reuse `◂ Name` from spec.md and its mirror for the other three edges (`▸`, `▴`, `▾`).
Done: test green; a driven look confirms a coworker panned off-screen shows as an edge marker, not
a silently-dropped label.

## 9. `wcag.test.ts` at every viewport position + `drive-office` check

- Extend `office/test/wcag.test.ts`'s `labels()` helper to loop every viewport position the floor
  can take at the test's fixed floor size, stepping by one cell (per spec.md) — generate the set
  with `clampViewport`, assert every position's labels still read at 4.5:1.
- `drive-office` session (see the `drive-office` skill): from a `.`-centred start, send
  `shift+Left` ×N, `shift+Up` ×N, `shift+Right` ×N, `shift+Down` ×N, reading the header back after
  each to confirm the viewport reaches each of the four corners and clamps there (not past it) —
  needs a header debug readout of `{viewport.x, viewport.y}` from task 7 (check the `drive-office`
  skill doc for its existing pattern for reading state back before inventing a new one).

Done for the whole plan: `mise run check` green, both checks above pass, a driven `drive-office`
session shows all four corners reached and clamped.
