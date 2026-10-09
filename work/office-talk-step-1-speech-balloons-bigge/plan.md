# Plan — office talk step 1: speech balloons, bigger and never overflowing

Source: `docs/plans/2026-10-08-office-talk-design.md` §3, §5 step 1 (ticket #70). Checked: none of it is
on main (`balloonLines` is still 26×3 with no hard-break; `paint.ts` clamps only the box's x).

All paths under `office/`; run tests with `cd office && bun test <file>`, typecheck `bun run typecheck`.
Each task = one commit, test written first (see it fail, then pass).

## Findings the engineer needs

- `kit/canvas.ts` `balloonLines(said)` → `string[]`; `Ink` balloon = `{ t:"balloon", lines, cx, top }` (logical px; `top` = speaker's head).
  Callers (`kit/draw.ts:140,216`, `kit/pets.ts:196`) pass only `said`, so the 34×4 default must live in `balloonLines`.
- `tui/paint.ts` draws a balloon in two places, each with its own clamping:
  - kitty: `inkInto` (the `else` branch, ~l.96) — box x clamped to the whole canvas `w`, never to the **viewport**; tail at `cx` even when the box was pushed away; a box wider than the canvas overflows.
  - block: `textLayer` (~l.169) — clamps the column to `g.cols` but not the width; `toCol` ignores `viewport.x/y`, so a panned view puts the box in the wrong cells.
- `clipFrame` (`tui/viewport.ts`) already drops balloons whose speaker is outside the viewport, so `inkInto`/`textLayer` only see visible speakers — but their boxes can still stick out of it.
- Rejoining wrapped lines (`lines.join(" ")`) is enough to re-wrap narrower at paint time; no change to `Ink`.

## Design (keep it this small)

One pure layout function, shared by both modes, in a new `kit/balloon.ts`, unit-agnostic (kitty feeds it screen px, blocks feed it cells):

```ts
export type Box = { x: number; y: number; w: number; h: number }
/** place one balloon: box centred on `cx`, bottom at `bottom`, clamped inside `area`, nudged up off `taken`; null = no room */
export function placeBox(size: { w: number; h: number }, cx: number, bottom: number, area: Box, taken: Box[], gap: number): (Box & { tail: number }) | null
```
`tail` is `cx` clamped to the box's span (minus an inset). Overlap policy: nudge up by `gap` steps; if it would
leave `area`, return null (the balloon waits — it is redrawn next frame, balloons are transient; the pets' exchanges already wait in `wide.ts`).

## Tasks

### 1 · `balloonLines`: 34×4, hard-break  (`kit/canvas.ts`, new `test/balloon.test.ts`)
Test first:
```ts
import { describe, expect, test } from "bun:test"
import { balloonLines } from "../kit/canvas"
describe("balloonLines", () => {
  test("hard-breaks a word longer than a line", () => {
    expect(balloonLines("x".repeat(80), 34, 4).every((l) => l.length <= 34)).toBe(true)
  })
  test("fuzz: never over the width, never over the rows, never empty for non-empty input", () => {
    let s = 12345; const rnd = () => (s = (s * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff
    for (let n = 0; n < 500; n++) {
      const words = Array.from({ length: 1 + Math.floor(rnd() * 30) }, () => "a".repeat(1 + Math.floor(rnd() * 80)))
      const width = 4 + Math.floor(rnd() * 31), rows = 1 + Math.floor(rnd() * 4)
      const out = balloonLines(words.join(" "), width, rows)
      expect(out.length).toBeGreaterThan(0); expect(out.length).toBeLessThanOrEqual(rows)
      for (const l of out) expect(l.length).toBeLessThanOrEqual(width)
    }
  })
  test("default is 34 x 4; overflow ends in ...", () => {
    const out = balloonLines("word ".repeat(60))
    expect(out.length).toBe(4); expect(out[3]!.endsWith("...")).toBe(true)
    expect(balloonLines("done - merged the thing")).toEqual(["done - merged the thing"])
  })
})
```
Code (replace the function; keep the flatten regexes as they are):
```ts
export function balloonLines(said: string, width = 34, rows = 4): string[] {
  const flat = /* existing flatten chain */
  const lines: string[] = []
  let line = ""
  for (let w of flat.split(" ").filter(Boolean)) {
    while (w.length > width) { // hard-break a word longer than a line
      if (line) { lines.push(line); line = "" }
      lines.push(w.slice(0, width)); w = w.slice(width)
    }
    if (line && line.length + 1 + w.length > width) { lines.push(line); line = w } else line = line ? `${line} ${w}` : w
  }
  if (line) lines.push(line)
  if (lines.length <= rows) return lines
  const kept = lines.slice(0, rows)
  kept[rows - 1] = kept[rows - 1]!.slice(0, width - 3).trimEnd() + "..."
  return kept
}
```
Update the doc comment (`~26 a line` → `34×4 by default`). Existing `rail.test.ts` / `pets.test.ts` must still pass.
Done: `bun test test/balloon.test.ts test/rail.test.ts test/pets.test.ts` green. Commit "office: balloonLines is 34x4 and hard-breaks long words".

### 2 · `placeBox` (`kit/balloon.ts`, `test/balloon.test.ts`)
Tests first (add to `balloon.test.ts`): box centred on `cx` when roomy; speaker at x=0 and x=area.w → box inside `area` and `tail` ∈ [box.x+inset, box.x+box.w-inset]; second box at the same `cx` has `y+h <= first.y` (nudged up); box wider than `area` → still inside is impossible, so callers shrink first (test `placeBox` returns null for `size.w > area.w`); no room above → null; fuzz 200 random (cx, bottom, size) with random `taken` → result is inside `area` and intersects nothing in `taken`, or null.
Code:
```ts
const hit = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
export function placeBox(size, cx, bottom, area, taken, gap) {
  if (size.w > area.w || size.h > area.h) return null
  const x = Math.min(Math.max(cx - size.w / 2, area.x), area.x + area.w - size.w)
  for (let y = bottom - size.h; y >= area.y; y -= gap) {
    const box = { x, y, w: size.w, h: size.h }
    if (!taken.some((t) => hit(box, t))) { const inset = Math.min(gap, size.w / 2); return { ...box, tail: Math.min(Math.max(cx, x + inset), x + size.w - inset) } }
  }
  return null
}
```
(If the box must sit below `area.y` at its first try, clamp the first `y` up to `area.y` rather than failing: start the loop at `Math.max(area.y, bottom - size.h)`.)
Done: `bun test test/balloon.test.ts` green. Commit "office: placeBox lays a balloon inside an area, off its neighbours".

### 3 · Kitty mode uses it (`tui/paint.ts` `inkInto`, `kittyImage`, `test/paint.test.ts`)
- Add optional `view?: { x: number; y: number; w: number; h: number }` (screen px) to `inkInto`; default the whole `w×h`. `kittyImage` passes `viewport` scaled by `g.k`; `wcag.test.ts` already calls `inkInto` without it (keep working).
- Balloon branch: `font=BODY, sc=zoom, lh=(font.h+1)*sc, pad=4*sc` (was 3). `maxCols = floor((view.w - 2*pad - 4)/(font.w*sc))`; `lines = maxCols < widest ? balloonLines(i.lines.join(" "), maxCols) : i.lines`; size from the lines; `taken` = a per-call array of boxes already placed (declare before the `for (const i of ink)`); `box = placeBox(size, i.cx*k, i.top*k - 3*k, view, taken, lh)`; `if (!box) continue`; `taken.push(box)`; fill box, tail `fill(box.tail - k, box.y + box.h, 2*k, 2*k, ROLE.prose)` (tail must also be inside `view`: bottom of the area is `view.y+view.h` — if tail would exit, skip the tail, it is only a nub); write lines.
- Tests first: render `inkInto` on a transparent `W×H` buffer with a long balloon (`balloonLines("x".repeat(80)+" tail words…")`) at `cx` = 0, mid, `floorW`, with `view` a sub-rectangle; assert every non-zero pixel lies inside `view`. Two balloons with `cx` 10 apart both render and their pixel sets in two separate renders don't intersect (render each alone, compare bounding boxes via the buffer).
Done: `bun test test/paint.test.ts test/wcag.test.ts` green; `bun run typecheck` clean. Commit "office: kitty balloons stay inside the viewport and off each other".

### 4 · Block mode uses it (`tui/paint.ts` `textLayer`, `test/paint.test.ts`)
- Balloon branch in cells: `toCol`/`toRow` of `cx`/`top` **minus the viewport's** (`toCol(i.cx - viewport.x)`, `toRow(i.top - viewport.y)`) — this also fixes the panned-view offset. `area = {x:0,y:0,w:cols0,h:rows0}`; shrink-wrap to `cols0 - 2`; `size = {w: widest+2, h: lines.length}`; `taken` array as in task 3 (gap 1); `placeBox(size, col, row - 1, area, taken, 1)`; skip on null; draw rows with `put`; tail: a `▾`-free approach is out of scope — block mode has no tail today, keep none.
- Tests first: `textLayer` with a 80-char-word balloon at `cx` = 0 and `floorW`, k=1, cw=1: every returned row, ANSI-stripped, has length `cols0` (no overflow), and the balloon text appears in full (hard-broken lines concatenated contain all the x's up to the cap). Panned viewport `{x:50,…}` with the speaker inside it: balloon text lands on the speaker's column, not 50 to the left. Two side-by-side speakers (`cx` 3 apart): both balloons' first lines visible, on different rows.
Done: `bun test test/paint.test.ts test/tui.test.ts` green. Commit "office: block-mode balloons wrap to the room and stay off each other".

### 5 · Two side-by-side speakers, end to end (`test/wide.test.ts` or `rail.test.ts`)
Test: `WideRoom`/`RailRoom` with two coworkers saying long lines at adjacent seats; render, feed the ink through `inkInto` (as `wcag.test.ts` does) and `textLayer`; assert no cell/pixel is claimed by both boxes (render each balloon alone vs together, boxes' union area == sum). Fix whatever this exposes in `draw.ts`; no change expected.
Done: green; commit "office: test two speakers' balloons don't collide".

### 6 · Look at it (no code unless it looks wrong)
Use the `drive-office` skill: start the TUI in kitty and in block mode, make a coworker at the far right/left edge say an 80-char word plus a long sentence (see `office/tui/main.ts:260` for how banter reaches a balloon, or `room.say(...)`), screenshot both. Attach to the thread. If something clips, add a failing test to task 3/4 first.
Done: two screenshots show a 34-wide, ≤4-line balloon fully inside the room at each edge.

### 7 · Docs
`office/AGENTS.md`: one sentence next to the `canvas.ts` entry — balloons are 34×4, hard-wrapped, placed by `kit/balloon.ts` so none leaves the viewport or overlaps another. Commit "office: AGENTS names the balloon law".

## Out of scope (named, not forgotten)
- The `... (v)` suffix for long replies — it needs `v` (step 4); `balloonLines` ends `...` only.
- Desktop (Cairo) surface: no balloon code in this repo besides the TUI's two paths; the `Ink` shape is unchanged, so it can adopt `placeBox` later.
- A "waiting" balloon is simply not drawn until it has room (it re-lays-out every frame).
- Re-wrapping by rejoining lines turns a hard-break into a space only when the viewport is narrower than 34 cols.

## Hand-off
Builder: tasks 1→7 in order, one commit each, `bun test` (whole suite) + `bun run typecheck` green before handing to review.
