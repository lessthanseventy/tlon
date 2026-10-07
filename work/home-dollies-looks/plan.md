# Dollies step 6 (Looks) — task breakdown

Each task is its own commit, in order; later tasks depend on earlier ones. "Verify" is the exact
command to run green before moving on. `mise run office:check` (install, typecheck, tests) is the
final gate for the whole step and is listed once at the end — run it after every task too, it's
cheap.

Two refinements from `spec.md`, found while grounding the UI tasks against `tui/main.ts`'s actual
shape (read, not re-decided — nothing here contradicts the approved spec):

- **"Live preview" (§3) is looking at your own figure in the room**, not a rendered pixel panel in
  the detail pane. The detail pane (`detail()` in `main.ts`) is text rows (`Row[]`, coloured
  segments) — no sprite rendering happens there today (`person`/`pet`/`card` cards are all prose +
  actions). `looks.json` is already re-read live (task 6), so cycling a part and looking at the
  room shows it within a tick. Simpler than a second render path, and nothing in the spec required
  the preview to live in the pane specifically.
- **The editor's 12×22 buffer is wider than the 14-row detail pane** (`DETAIL = 14` in `main.ts`).
  It renders a viewport of however many rows fit (title + legend + footer leave ~11), scrolling as
  the cursor nears an edge — the same "pan before you'd need to" the office's own floor-scroll
  design (§4 of the home/dollhouse plan) uses, at a much smaller scale.

## Task 1 — `skinRole` on `Look`, used by `paints()`

**Files:** `office/kit/sprites.ts`, `office/test/sprites.test.ts` (new).

Failing test first:

```ts
// office/test/sprites.test.ts
import { describe, expect, test } from "bun:test"
import { lookOf, paints } from "../kit/sprites"
import { ROLE } from "../kit/palette"

describe("paints", () => {
  test("skin (f) is ROLE.prose when the look has no skinRole", () => {
    expect(paints("#fff", lookOf("hronir")).f).toBe(ROLE.prose)
  })
  test("skin (f) follows look.skinRole when set", () => {
    expect(paints("#fff", { ...lookOf("hronir"), skinRole: "builder" }).f).toBe(ROLE.builder)
  })
})
```

Implementation — `office/kit/sprites.ts`:

```ts
export type Look = {
  hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
  skinRole?: Role
}
// ...
export function paints(shirt: string, look: Look): Record<string, string> {
  return { h: ROLE[look.hairRole], f: look.skinRole ? ROLE[look.skinRole] : ROLE.prose, k: ROLE.fieldInk, s: shirt, p: ROLE.meta, b: ROLE.structure, y: ROLE.body, c: ROLE.structure, g: ROLE.key, e: ROLE.key, w: ROLE.prose, r: ROLE.alarm }
}
export const SKIN_ROLES: Role[] = ["builder", "surveyor", "reviewer", "assistant", "planner", "body"]
```

**Verify:** `cd office && bun test test/sprites.test.ts` (red, then green). `lookOf`'s output is
unchanged for every existing caller (no `skinRole` ever set by it), so `wide.test.ts`/
`pets.test.ts`/`tui.test.ts` stay green untouched.

## Task 2 — outfit and accessory overlays

**Files:** `office/kit/sprites.ts`, `office/test/sprites.test.ts`.

Failing test (append):

```ts
import { figure } from "../kit/sprites"

test("an outfit overlays the torso row, front view", () => {
  const base = figure(lookOf("hronir"), null, false, false, "down", "stand", 0, false)
  const dressed = figure({ ...lookOf("hronir"), outfit: "hoodie" }, null, false, false, "down", "stand", 0, false)
  expect(dressed[10]).not.toBe(base[10])
  expect(dressed[10]).toBe(".oooooooooo.")
})
test("no outfit/accessory set renders exactly as before (regression)", () => {
  expect(figure(lookOf("yu"), "builder", true, false, "down", "stand", 0, false))
    .toEqual(figure(lookOf("yu"), "builder", true, false, "down", "stand", 0, false))
})
```

Implementation — `office/kit/sprites.ts`, extend `Look` and `figure()`:

```ts
export type Outfit = "hoodie" | "labcoat"
export const OUTFIT: Record<Outfit, Gear> = {
  hoodie:  { front: { 10: ".oooooooooo." }, back: { 10: ".oooooooooo." }, side: { 10: "..oooooooo.." } },
  labcoat: { front: { 9: ".wwwwwwwwww.", 10: "ww........ww" }, back: { 9: ".wwwwwwwwww." }, side: { 9: "wwwwwwwwwwww" } },
}
export type Accessory = "glasses" | "headphones"
export const ACCESSORY: Record<Accessory, Gear> = {
  glasses:    { front: { 6: "..kk..kk...." }, side: { 6: ".kk........." } },
  headphones: { front: { 5: ".k........k." }, back: { 5: ".k........k." }, side: { 5: "k..........." } },
}
export type Look = { /* …as task 1… */ skinRole?: Role; outfit?: Outfit; accessory?: Accessory }
```

In `figure()`, right after the `rows = [...]` branch (both the `side` and non-`side` paths
converge before `const gear = GEAR[...]`), insert:

```ts
if (look.outfit) overlay(rows, view === "front" ? OUTFIT[look.outfit].front : view === "back" ? OUTFIT[look.outfit].back : OUTFIT[look.outfit].side)
if (look.accessory) overlay(rows, view === "front" ? ACCESSORY[look.accessory].front : view === "back" ? ACCESSORY[look.accessory].back : ACCESSORY[look.accessory].side)
```

— before the existing `const gear = GEAR[archetype ?? ""]` line, so archetype gear still overlays
*on top* (§5.1: "the look says who; the hard hat says what they are").

`paints()` needs `o`/`w`-as-labcoat already covered (`w: ROLE.prose` exists; reuse it for labcoat
— no new paint entry) and a new `o` entry for the hoodie: add `o: ROLE.body` to the returned map.

**Verify:** `cd office && bun test test/sprites.test.ts`. Then `mise run office:run`, open yourself
(`l` won't exist until task 13 — for now, eyeball by temporarily setting `outfit: "hoodie"` in a
scratch script or the next task's test) to confirm the row reads as a hoodie, not noise; revert
the scratch check.

## Task 3 — `custom` sprite override

**Files:** `office/kit/sprites.ts`, `office/test/sprites.test.ts`.

Failing test:

```ts
test("a custom view replaces the generated base but keeps gear and the sit/mirror rules", () => {
  const custom = { front: Array.from({ length: 20 }, (_, i) => (i === 0 ? "kkkkkkkkkkkk" : "............")) }
  const rows = figure({ ...lookOf("hronir"), custom }, "builder", false, false, "down", "stand", 0, false)
  expect(rows[0]).toBe("kkkkkkkkkkkk")
  const sitting = figure({ ...lookOf("hronir"), custom }, null, false, false, "down", "sit", 0, false)
  expect(sitting.length).toBe(14)
  const right = figure({ ...lookOf("hronir"), custom: { side: custom.front } }, null, false, false, "right", "stand", 0, false)
  expect(right[0]).toBe([...custom.front[0]!].reverse().join(""))
})
```

Implementation — `Look` gains `custom?: Partial<Record<"front" | "side" | "back", string[]>>`;
in `figure()`, replace the `if (view === "side") { … } else { … }` block's *assignment* of `rows`
with:

```ts
rows = look.custom?.[view] ? [...look.custom[view]!] : view === "side" ? /* existing side branch */ : /* existing front/back branch */
```

(i.e. wrap the two existing branches as the fallback of a ternary/early-return on
`look.custom?.[view]`; outfit/accessory/gear overlay, the `lead`/`boss` overlay, the mirror and the
sit-slice all stay exactly where they are, after this check.)

**Verify:** `cd office && bun test test/sprites.test.ts`.

## Task 4 — `office/kit/looks.ts`: the override store

**Files:** `office/kit/looks.ts` (new), `office/test/looks.test.ts` (new).

Failing test:

```ts
// office/test/looks.test.ts
import { describe, expect, test } from "bun:test"
import { overrideFor, useLookOverrides } from "../kit/looks"

describe("look overrides", () => {
  test("nobody is overridden until useLookOverrides is called", () => {
    expect(overrideFor("nobody-set-yet")).toBeUndefined()
  })
  test("useLookOverrides replaces the whole table", () => {
    useLookOverrides({ yu: { skinRole: "builder" } })
    expect(overrideFor("yu")).toEqual({ skinRole: "builder" })
    expect(overrideFor("hronir")).toBeUndefined()
    useLookOverrides({})
    expect(overrideFor("yu")).toBeUndefined()
  })
})
```

Implementation:

```ts
// office/kit/looks.ts
import type { Look } from "./sprites"
export type LookOverride = Partial<Look>
let overrides: Record<string, LookOverride> = {}
/** take the machine's looks.json if it changed — same shape as palette.ts's useRoles */
export function useLookOverrides(o: Record<string, LookOverride>) { overrides = o }
export function overrideFor(name: string): LookOverride | undefined { return overrides[name] }
```

Then wire the one call site, `office/kit/sim.ts` (currently `look: lookOf(r.agent)`):

```ts
look: { ...lookOf(r.agent), ...overrideFor(r.agent) },
```

(add `import { overrideFor } from "./looks"` alongside the existing `lookOf` import.)

**Verify:** `cd office && bun test test/looks.test.ts`. `bun test` (whole suite) to confirm `sim.ts`
still type-checks and nothing else broke — `overrideFor` returns `undefined` for every name until
task 6 populates the table, so `wide.test.ts`/`pets.test.ts` render unchanged.

## Task 5 — `~/.config/tlon/looks.json`, polled live in the TUI

**Files:** `office/tui/main.ts`. No new test — `main.ts`'s file-poll (`followPalette`) has none
today either; this is wiring, verified by running the TUI (per `office/AGENTS.md`: "A frame change
is seen, not assumed").

Mirror `PALETTE`/`followPalette` (`main.ts` lines ~45–103) exactly:

```ts
import { useLookOverrides } from "../kit/looks"
import type { LookOverride } from "../kit/looks"
// beside `const PALETTE = …`:
const LOOKS = process.env.TLON_LOOKS ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/looks.json")
let looksSeen = ""
function followLooks(): boolean {
  try {
    const real = realpathSync(LOOKS), seen = `${real}@${statSync(real).mtimeMs}`
    if (seen === looksSeen) return false
    looksSeen = seen
    useLookOverrides(JSON.parse(readFileSync(real, "utf8")) as Record<string, LookOverride>)
    return true
  } catch { return false }
}
```

Call `followLooks()` everywhere `followPalette()` is called (the per-tick poll; grep
`followPalette()` in `main.ts` for the exact call sites — there is one steady-state poll loop),
OR-ing its result into whatever triggers a redraw/`changed()` there.

**Verify:** `mise run office:check` (typecheck catches a wiring slip); then `mise run office:run`
with a scratch `~/.config/tlon/looks.json` (or `TLON_LOOKS=/tmp/x.json mise run office:run`)
containing `{"<a bench name>": {"skinRole": "builder"}}` and confirm that coworker's skin changes
within ~1s with no restart.

## Task 6 — `office/kit/snap.ts`: Lab-distance nearest char

**Files:** `office/kit/snap.ts` (new), `office/test/snap.test.ts` (new).

Failing test:

```ts
// office/test/snap.test.ts
import { describe, expect, test } from "bun:test"
import { nearestChar } from "../kit/snap"

describe("nearestChar", () => {
  test("an exact role hex snaps to its own char", () => {
    const paint = { k: "#0A0A0A", y: "#FFB000", p: "#B4A5D6" }
    expect(nearestChar("#FFB000", paint)).toBe("y")
  })
  test("a near-miss snaps to the closest role, not alphabetically first", () => {
    const paint = { k: "#0A0A0A", y: "#FFB000" } // far apart; anything warm-ish goes to y
    expect(nearestChar("#FFA000", paint)).toBe("y")
  })
  test("fully transparent is always the clear char, regardless of colour", () => {
    expect(nearestChar("#FFB000", { k: "#0A0A0A" }, 0)).toBe(".")
  })
})
```

Implementation:

```ts
// office/kit/snap.ts — pixel RGBA → the nearest char in a figure's paint map (Lab distance).
// Pure: no PNG decoding here (office/cli.ts owns that) so this stays reachable from the TUI build.
function srgbToLinear(c: number) { const s = c / 255; return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4 }
function hexToLab(hex: string): [number, number, number] {
  const r = srgbToLinear(parseInt(hex.slice(1, 3), 16)), g = srgbToLinear(parseInt(hex.slice(3, 5), 16)), b = srgbToLinear(parseInt(hex.slice(5, 7), 16))
  const x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047, y = r * 0.2126 + g * 0.7152 + b * 0.0722, z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883
  const f = (t: number) => (t > 0.008856 ? Math.cbrt(t) : (903.3 * t + 16) / 116)
  const fx = f(x), fy = f(y), fz = f(z)
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
}
/** the char in `paint` ("#f00" etc. hex values) nearest `hex` by Lab distance; alpha below `cut` (0-255) → "." */
export function nearestChar(hex: string, paint: Record<string, string>, alpha = 255, cut = 128): string {
  if (alpha < cut) return "."
  const [L, a, b] = hexToLab(hex)
  let best = "", bestD = Infinity
  for (const [ch, h] of Object.entries(paint)) {
    const [L2, a2, b2] = hexToLab(h), d = (L - L2) ** 2 + (a - a2) ** 2 + (b - b2) ** 2
    if (d < bestD) { bestD = d; best = ch }
  }
  return best
}
```

**Verify:** `cd office && bun test test/snap.test.ts`.

## Task 7 — `office/cli.ts`: `import-sprite`, and the mise task

**Files:** `office/cli.ts` (new), `office/package.json` (add `pngjs` + `@types/pngjs` to
`dependencies`/`devDependencies`), `tasks/office.toml`, `office/test/cli.test.ts` (new).

`pngjs` is imported **only** here — not from anything under `kit/` or `tui/` (Andrew's note on
thread 134; `office/AGENTS.md`'s "one runtime dep" is about what `office:build` actually bundles
from `tui/main.ts`'s import graph, which never reaches `cli.ts`).

Failing test first (round trip, §8's check — build a PNG in-memory with `pngjs`, no fixture file):

```ts
// office/test/cli.test.ts
import { describe, expect, test } from "bun:test"
import { PNG } from "pngjs"
import { snapSheet } from "../cli"
import { lookOf, paints } from "../kit/sprites"

function solidPng(w: number, h: number, hex: string): Buffer {
  const png = new PNG({ width: w, height: h })
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
  for (let i = 0; i < w * h; i++) { png.data[i * 4] = r!; png.data[i * 4 + 1] = g!; png.data[i * 4 + 2] = b!; png.data[i * 4 + 3] = 255 }
  return PNG.sync.write(png)
}

describe("import-sprite round trip", () => {
  test("a 12x22 solid-colour PNG snaps to one char, repeated", () => {
    const paint = paints("#fff", lookOf("hronir"))
    const buf = solidPng(12, 22, paint.k!) // fieldInk — the darkest, least ambiguous role
    const rows = snapSheet(buf, 12, 22, paint)
    expect(rows).toHaveLength(22)
    expect(new Set(rows.map((r) => new Set(r).size === 1 ? [...r][0] : "?"))).toEqual(new Set(["k"]))
  })
  test("refuses a size that isn't 12x22 or 48x22", () => {
    expect(() => snapSheet(solidPng(10, 10, "#000000"), 10, 10, paints("#fff", lookOf("hronir")))).toThrow(/12x22|48x22/)
  })
})
```

Implementation — `office/cli.ts`:

```ts
#!/usr/bin/env bun
// import-sprite: a PNG (12x22, one view, or 48x22, four views side by side) → looks.json's
// `custom` field for an agent, every pixel snapped to the nearest role via kit/snap.ts.
// The only file in office/ that imports pngjs — kept out of kit/ and tui/ so the compiled TUI's
// one runtime dep (office/AGENTS.md) stays just that.
import { PNG } from "pngjs"
import { readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { nearestChar } from "./kit/snap"
import { lookOf, paints, shirtOf, type Look } from "./kit/sprites"

const VIEWS = ["front", "side", "back", "side"] as const // the 48x22 sheet's four columns; the 4th (back-right) is unused today

export function snapSheet(buf: Buffer, w: number, h: number, paint: Record<string, string>): string[] {
  if (h !== 22 || (w !== 12 && w !== 48)) throw new Error(`expected 12x22 or 48x22, got ${w}x${h}`)
  const png = PNG.sync.read(buf), rows: string[] = []
  for (let y = 0; y < h; y++) {
    let row = ""
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4
      row += nearestChar(`#${[0, 1, 2].map((k) => png.data[i + k]!.toString(16).padStart(2, "0")).join("")}`, paint, png.data[i + 3]!)
    }
    rows.push(row)
  }
  return rows
}

function sheetToViews(rows: string[], w: number): Partial<Record<"front" | "side" | "back", string[]>> {
  if (w === 12) return { front: rows }
  const out: Partial<Record<"front" | "side" | "back", string[]>> = {}
  for (let v = 0; v < 3; v++) out[VIEWS[v]!] = rows.map((r) => r.slice(v * 12, v * 12 + 12))
  return out
}

if (import.meta.main) {
  const [cmd, path, name] = process.argv.slice(2)
  if (cmd !== "import-sprite" || !path || !name) { console.error("usage: import-sprite <path.png> <agent-name>"); process.exit(1) }
  const buf = readFileSync(path), { width, height } = PNG.sync.read(buf)
  const current: Look = lookOf(name)
  const paint = paints(shirtOf(null), current)
  let rows: string[]
  try { rows = snapSheet(buf, width, height, paint) } catch (e) { console.error((e as Error).message); process.exit(1) }
  for (const r of rows) console.log(r)
  const looksPath = process.env.TLON_LOOKS ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/looks.json")
  const all = JSON.parse((() => { try { return readFileSync(looksPath, "utf8") } catch { return "{}" } })())
  all[name] = { ...all[name], custom: sheetToViews(rows, width) }
  writeFileSync(looksPath, JSON.stringify(all, null, 2))
  console.log(`wrote ${looksPath} (${name})`)
}
```

`tasks/office.toml` — add beside `office:run`:

```toml
["office:import-sprite"]
description = "office: import a 12x22 (or 48x22, four views) PNG into looks.json as that agent's custom sprite — every pixel snapped to the nearest palette role"
dir = "office"
run = "bun cli.ts import-sprite \"$@\""
```

`office/package.json`: add `"pngjs": "^7.0.0"` to `dependencies`, `"@types/pngjs": "^6.0.5"` to
`devDependencies`.

**Verify:** `cd office && bun install && bun test test/cli.test.ts`, then
`mise run office:import-sprite -- /path/to/a-12x22.png some-name` against a real hand-drawn PNG
and inspect `~/.config/tlon/looks.json`.

## Task 8 — WCAG: every skin tone against every room background

**Files:** `office/test/wcag.test.ts`.

Failing test (append to the existing `describe("WCAG 1.4.3…")` block, or a new `describe`):

```ts
import { SKIN_ROLES } from "../kit/sprites"

describe("WCAG: skin tones against the rooms", () => {
  test("every skin role reads at 3:1 (large-shape contrast) against every room background in use today", () => {
    // the fills a figure can stand in front of: the ground plus the room's floor/panel tones —
    // re-run against tiles.ts's floors once step 1 lands them (spec.md §6)
    const backgrounds = [ROLE.ground, ROLE.panel, ROLE.raised, ROLE.edge]
    for (const skin of SKIN_ROLES) for (const bg of backgrounds) {
      expect({ skin, bg, ratio: contrast(ROLE[skin], bg) >= 3 }).toMatchObject({ ratio: true })
    }
  })
})
```

(3:1 — WCAG's large-shape minimum — not the 4.5:1 text minimum `MIN_CONTRAST` holds elsewhere: a
figure is art, not a text label, and the existing roles were not all picked against each other at
text contrast. If any pair fails even 3:1, that pair is a real finding — fix by excluding it from
`SKIN_ROLES` for now and naming the follow-up, don't lower the bar.)

**Verify:** `cd office && bun test test/wcag.test.ts`.

## Task 9 — the look card

**Files:** `office/tui/main.ts`.

Follows the `pet` card's exact shape (`main.ts:846`, text rows + keyed actions — no new render
path). New `Mode` variant: `{ kind: "look"; name: string }`.

- Open: wherever a coworker or yourself is picked (the `person` card's existing action list,
  `main.ts` around line 753's `{ key: "e", label: … }` pattern) add `{ key: "l", label: "look",
  run: () => open({ kind: "look", name }) }`.
- `detail()`, new `case "look"`: rows list the current resolved look (`{ ...lookOf(name),
  ...overrideFor(name) }`) one field per line — hair, hair colour, skin, outfit, accessory — each
  a `Row` whose `open()` cycles that field forward through its catalogue
  (`HAIRS`/`HAIR_ROLES`/`SKIN_ROLES`/`[...Object.keys(OUTFIT), "none"]`/
  `[...Object.keys(ACCESSORY), "none"]`) and writes the *draft* (component state, not yet saved).
  Actions: `{ key: "⏎", label: "save", run: … }` (read-merge-write `looks.json`: load the file,
  set `all[name] = draft`, write back — mirrors `cli.ts`'s read-merge-write), back/esc discards the
  draft. A one-line hint row says "look at the room — it updates live" per this plan's preview
  refinement above.
- State: one module-level `let lookDraft: LookOverride | null` (parallels existing singletons like
  `input`/`confirm`), reset to `{ ...lookOf(name), ...overrideFor(name) }` on open, cleared on
  close/save.

**Verify:** `mise run office:check` (typecheck); `mise run office:run`, open a coworker, press `l`,
cycle each field, save, confirm `~/.config/tlon/looks.json` gained the entry and the room's figure
changed. Record the session with the `drive-office` skill if a repeatable check is wanted later —
not required for this task's own done.

## Task 10 — the editor

**Files:** `office/tui/main.ts`.

New `Mode` variant: `{ kind: "look-editor"; name: string; view: "front" | "side" | "back" }`
(the 4th, mirrored view, is derived — editing `side` edits both left and right at once, same as
`figure()`'s own mirror-on-`right`). Reachable from the look card (task 9) via `{ key: "e", label:
"draw a custom look", run: () => open({ kind: "look-editor", name, view: "front" }) }`.

- Buffer: `let editBuf: Record<"front" | "side" | "back", string[]> | null`, seeded from
  `lookDraft.custom` if present, else 22 rows of `"............"`. Cursor `{ x: number; y: number }`
  and a scroll offset so the visible window (≈11 of the 22 rows, given `DETAIL = 14` minus a
  legend line and a footer) follows the cursor — pan only when the cursor would leave the window,
  exactly the dead-zone rule §4 of the master plan uses for the room's own viewport, at pixel scale
  instead of tile scale.
- Keys: arrows move the cursor (clamped 0..11 / 0..21); any key in `paints()`'s legend
  (`h f k s p b y c g e w r o`, shown as a legend `Row` at the top of the pane) paints that char at
  the cursor, mirrored to `11 - x` when `m` (mirror, default on) is active; `.` clears; `1`/`2`/`3`
  switch `view` (front/side/back), each keeping its own buffer; `⏎` writes `editBuf` into
  `lookDraft.custom` and returns to the look card (task 9) — not yet to `looks.json`, so `esc` from
  the card after this still discards cleanly; `esc` here alone discards just this view's edits back
  to what it was on entry.
- Rendering the grid as text rows: each sprite row becomes one `Row` whose `segs` is 12 one-char
  segments, `{ s: "█", fg: ROLE[paintFor(ch)] }` (or `{ s: "·", fg: ROLE.inactive }` for `.`), cursor
  row/col inverted (swap `fg`/`bg`) so it's visible without colour being the only signal (an
  underline or bracket around the cursor cell works too — pick one and keep it consistent with how
  the rest of the TUI marks "selected", e.g. `sel` elsewhere).

**Verify:** `mise run office:check`; `mise run office:run`, open the editor from a look card, paint
a few cells across a pan boundary, switch views, save, confirm the look card's draft now shows
`custom` is set and the room renders it. This task has no unit test — it is drawing into a `Frame`-
adjacent text pane, the same category `office/AGENTS.md` already calls "seen, not assumed."

## Final gate

`mise run office:check` (install, typecheck, the whole `bun test` suite) green, then `mise run
check` (the repo-wide gate: names + server + adapters + office + the manual) green before this
step's PR goes up. Each task above is its own commit on `work/home-dollies-looks`; nothing here
blocks step 1/4/5/7 — this track (§8: "Dollies … steps 6 → 7") touches only `office/kit/sprites.ts`,
`office/kit/looks.ts`, `office/kit/snap.ts`, `office/cli.ts`, `office/tui/main.ts`,
`office/test/*`, `tasks/office.toml`, `office/package.json`.
