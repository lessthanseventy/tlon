# Plan — toy step 3: the bathroom, and Nina's wet paws (ticket #54)

Spec: `docs/plans/2026-10-08-office-as-a-toy-design.md` §4, §8 step 3. Office-only (`office/`); no server change.
Branch off main, rebase onto main after #242 (toy step 2) lands; `office/tui/main.ts` is the only shared file (T6, one line).
Run everything from `office/`. Gate per task: `bun test test/<file>.test.ts`; end: `mise run office:check`.

## Decisions (the four the tech lead asked for)

1. **Where.** The office column's lower pocket: `BATH = {x:22, y:152, w:58, h:31}`, door gap in its bottom wall at `x=50`, opening onto the HALL runner (`HALL=191`). Verified free of `plan.blocks`, the closet (x 2–14), Nina's lane (`OFF_LANE=94`) and the plant at (84,182) at 540/696/900 — `OFF_W` is width-independent, so the room is the same at every width. It is a `TileKind` `"bathroom"` (a `Tile`, like `kitchen`), added to `DEFAULT_OFFICE`. Not the home annex's `HomeTileKind` "bathroom" (different catalogue, `kit/home.ts`) — no clash, don't touch it.
2. **Prints** are a Sim-owned overlay `Print = {x, y, at, until}` (`Sim.prints`), pruned by tick. Nina carries only `wet` (a tick, like `stretch`); she holds no print state. Fade is `fadeStage(p, tick)` — a pure function of the tick.
3. **Fall-in** is one extra seeded draw at the tub (`FALL_ODDS`), the same trip with a longer `wet` and longer print life.
4. **Test contract.** The sim draws from `Math.random`, not a passed rng, so "mulberry32(seed)" means `seeded(seed, …)` from `test/golden.ts` (it installs mulberry32 as `Math.random`). A trip is started with `catDo("drink")` (no waiting on chance); the asserted facts are exact: the cat's tile sequence through the door, and every print's `{x,y,at,until}`. **No new draw is added to a path that doesn't take the trip**: the trip's trigger is the unused slice `0.95 < r ≤ 0.97` of the idle roll `r` that `stepCat` already draws (so existing seeded sequences move only where that slice fell). Goldens re-hash anyway (T6).

Constants live in `kit/bathroom.ts`; tests import them, so a layout nudge doesn't break them. The two exact-sequence tests in T3 pin literals once, from a first run — that is the contract.

## T1 — `kit/bathroom.ts`: geometry, prints, fade, door (pure)

Files: new `office/kit/bathroom.ts`, new `office/test/bathroom.test.ts`.

Test first (`test/bathroom.test.ts`):

```ts
import { describe, expect, test } from "bun:test"
import { BATH, DOOR, FALL_LIFE, LIFE, doorOpen, fadeStage, layPrint, prune } from "../kit/bathroom"

describe("prints", () => {
  test("a print lives LIFE ticks (a minute at 100 ms), longer when she fell in", () => {
    expect(layPrint(10, 20, 100, false)).toEqual({ x: 10, y: 20, at: 100, until: 100 + LIFE })
    expect(layPrint(10, 20, 100, true).until).toBe(100 + FALL_LIFE)
    expect(FALL_LIFE).toBeGreaterThan(LIFE)
  })
  test("fadeStage is 0 fresh, rises to 3 just before it goes, and prune drops it at until", () => {
    const p = layPrint(0, 0, 0, false)
    expect([0, LIFE / 3 - 1, LIFE / 3, (2 * LIFE) / 3, LIFE - 1].map((t) => fadeStage(p, t))).toEqual([0, 0, 1, 2, 2])
    expect(fadeStage(p, LIFE)).toBe(3)
    expect(prune([p], LIFE - 1)).toHaveLength(1)
    expect(prune([p], LIFE)).toHaveLength(0)
  })
  test("they go one by one: laid in order, they vanish in order", () => {
    const ps = [0, 12, 24].map((t) => layPrint(t, 0, t, false))
    expect(prune(ps, LIFE + 12).map((p) => p.at)).toEqual([24])
  })
})

describe("the room", () => {
  test("the door is in the bottom wall, inside the box", () => {
    expect(DOOR.y).toBe(BATH.y + BATH.h)
    expect(DOOR.x).toBeGreaterThan(BATH.x)
    expect(DOOR.x).toBeLessThan(BATH.x + BATH.w)
  })
  test("the door is open while anyone is at it, and for HOLD ticks after, else shut", () => {
    const at = { x: DOOR.x, y: DOOR.y - 2 }, far = { x: 300, y: 100 }
    expect(doorOpen([at], 50, -1000)).toBe(true)
    expect(doorOpen([far], 50, -1000)).toBe(false)
    expect(doorOpen([far], 50, 45)).toBe(true) // someone was at it 5 ticks ago
    expect(doorOpen([far], 80, 45)).toBe(false)
  })
})
```

Code (`kit/bathroom.ts`):

```ts
// The bathroom off the hall: its geometry, Nina's wet pawprints and how they fade, and when the
// door stands open. Pure — the sim lays and prunes prints, the tile draws them.
import type { Pt } from "./sim"

export const BATH = { x: 22, y: 152, w: 58, h: 31 }
/** the gap in the bottom wall: where the room meets the hall runner */
export const DOOR = { x: 50, y: BATH.y + BATH.h }
/** the tub's rim, where she sits to drink, and the floor in front of it she hops up from */
export const RIM = { x: 38, y: 166 }
export const RIM_FLOOR = { x: 38, y: 174 }
/** where a coworker stands at the sink */
export const SINK = { x: 68, y: 172 }
/** ticks (100 ms) a print lasts: a minute; she fell in, a good while longer */
export const LIFE = 600
export const FALL_LIFE = 1500
/** ticks the door stays open after someone was at it */
export const HOLD = 8
/** a pawprint every STRIDE pixels she walks while her paws are wet */
export const STRIDE = 6
/** ticks she drinks; ticks her paws stay wet after (more after a fall) */
export const DRINK = 60
export const WET = 240
export const FALL_WET = 700
/** the chance a drinking trip ends in the tub */
export const FALL_ODDS = 0.05

export type Print = { x: number; y: number; at: number; until: number }

export const layPrint = (x: number, y: number, at: number, fell: boolean): Print => ({ x, y, at, until: at + (fell ? FALL_LIFE : LIFE) })
/** 0 fresh … 2 nearly gone, 3 gone: thirds of the print's own life */
export function fadeStage(p: Print, tick: number): 0 | 1 | 2 | 3 {
  if (tick >= p.until) return 3
  return Math.floor(((tick - p.at) * 3) / (p.until - p.at)) as 0 | 1 | 2
}
export const prune = (ps: Print[], tick: number): Print[] => ps.filter((p) => tick < p.until)

/** the door is open while someone (anyone walking or settled) is within reach of it, and HOLD ticks after */
export function doorOpen(near: Pt[], tick: number, lastAt: number): boolean {
  if (near.some((p) => Math.abs(p.x - DOOR.x) <= 6 && Math.abs(p.y - DOOR.y) <= 6)) return true
  return tick - lastAt <= HOLD
}
```

Done: `bun test test/bathroom.test.ts` green. Commit: `office: the bathroom's geometry and Nina's pawprints (pure)`.

## T2 — the tile and the pastime

Files: new `office/kit/tiles/bathroom.ts`; edit `office/kit/tiles.ts` (`TileKind`, `DEFAULT_OFFICE`), `office/kit/floor.ts` (`FACTORIES`, `LOUNGE_KINDS`), `office/kit/sim.ts` (`Pastime`, `LOUNGING`, `MOODS`); test in `office/test/pastimes.test.ts`.

Test first, appended to `test/pastimes.test.ts` (uses its `chance`, `office`, `inside`):

```ts
describe("the bathroom", () => {
  test("it is a pastime: the floor plan has a spot at the sink and it is in the lounge list", () => {
    const p = widePlan(696), s = p.lounge.filter((x) => x.kind === "bathroom")
    expect(s).toHaveLength(1)
    expect(s[0]).toMatchObject({ x: 68, y: 172, aisle: 191 })
  })
  test("no wall or fixture is walked through: every route to the sink stays out of the blocks", () => {
    const p = widePlan(696), l = p.layout(viewOf(office(["yu"]), 1) as never), spot = p.lounge.find((x) => x.kind === "bathroom")!
    const blocks = p.blocks(l)
    const hit = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
    for (const from of [{ x: 150, y: 116 }, { x: 94, y: 160 }, { x: 450, y: 176 }]) {
      const pts = [from, ...p.route(from.x, from.y, spot)]
      for (let i = 1; i < pts.length; i++) for (let t = 0; t <= 1; t += 0.05) {
        const x = pts[i - 1]!.x + (pts[i]!.x - pts[i - 1]!.x) * t, y = pts[i - 1]!.y + (pts[i]!.y - pts[i - 1]!.y) * t
        expect(hit(x, y)).toBeUndefined()
      }
    }
  })
  test("someone idle goes in, and is back out on the floor again", () => chance(0, () => {
    const room = new WideRoom(696), a = viewOf(office(["yu"]), 1), r = inside(room)
    let seen = false
    for (let i = 0; i < 6000 && !seen; i++) { room.step(a); seen = [...r.actors.values()].some((x) => x.spot.kind === "bathroom" && !x.moving && !x.path.length) }
    expect(seen).toBe(true)
  }))
})
```

(`chance(0)` takes every chance: if the plan's first free lounge spot isn't the bathroom, the third test still passes once the spot is picked — if it can't reach it in 6000 ticks, stop and make the test force it with `r.actors.get("yu")` / `idleGoal` instead of loosening the bound.)

Code:

- `kit/sim.ts`: add `"bathroom"` to `Pastime`, to `LOUNGING`, and `bathroom: ["~", "♪"]` to `MOODS`. `moment()` needs no change (default 1).
- `kit/tiles.ts`: `TileKind` gains `"bathroom"`; `DEFAULT_OFFICE.tiles` gains `{ kind: "bathroom", at: [0, 0] }` **last** (idle-target order is load-bearing; last keeps every earlier pick).
- `kit/floor.ts`: `FACTORIES.bathroom = bathroomTile`; append `"bathroom"` to the end of `LOUNGE_KINDS`.
- `kit/tiles/bathroom.ts`:

```ts
import { ROLE, tint } from "../palette"
import { BATH, DOOR, SINK } from "../bathroom"
import type { Rect, Tile } from "../tiles"
import { at } from "../tiles"
import type { Layout } from "../../rooms/wide"
import { HALL } from "../../rooms/wide"

/** walls (the bottom wall split at the door), the tub, the sink and the toilet */
export const WALLS: Rect[] = [
  { x: BATH.x, y: BATH.y, w: BATH.w, h: 2 },
  { x: BATH.x, y: BATH.y, w: 2, h: BATH.h },
  { x: BATH.x + BATH.w - 2, y: BATH.y, w: 2, h: BATH.h },
  { x: BATH.x, y: DOOR.y - 1, w: DOOR.x - 5 - BATH.x, h: 2 },
  { x: DOOR.x + 5, y: DOOR.y - 1, w: BATH.x + BATH.w - (DOOR.x + 5), h: 2 },
]
export const TUB: Rect = { x: 26, y: 156, w: 30, h: 14 }
const SINK_BOX: Rect = { x: 62, y: 156, w: 12, h: 8 }, TOILET: Rect = { x: 66, y: 164, w: 10, h: 8 }

export function bathroomTile(): Tile<Layout> {
  return {
    kind: "bathroom",
    blocks: () => [...WALLS, TUB, SINK_BOX, TOILET],
    spots: () => ({ bathroom: [at(SINK.x, SINK.y, HALL, "up", "bathroom")] }),
    draw(sc, _a, _l, _m, sim) { /* T5 draws it; T2 draws the floor, walls, fixtures and the shut/open door */ },
  }
}
```

Fill `draw` now with the static room (tile floor `tint(ROLE.structure, ROLE.ground, 0.15)` over `BATH`, walls `ROLE.structure`, tub white with a drip pixel on `sc.f % 8 === 0`, sink, toilet with the lid a lighter rect) via `sc.item(BATH.y + BATH.h, …)`, and the door gap: shut = a `ROLE.borderInactive` rect over the gap; open = leaf drawn swung to one side. Open/closed from `doorOpen([...sim.at("bathroom"), sim.cat, …], sc.tick, lastAt)` — `lastAt` is a module-level `let` the tile updates when `doorOpen` is true (it is draw-time state, not sim state; it only decides a pixel).

Gotcha: the spot's `aisle` is `HALL`, so `plan.route` (`kit/floor.ts`) goes lane → down to HALL → along the hall → up the door at `x=50`; it never crosses a wall. The wall test above is the proof; if it fails the spot is wrong, not the wall.

Done: `bun test test/pastimes.test.ts test/wide.test.ts` green (wide.test already walks every route between every spot through every tile's blocks). Commit: `office: the bathroom tile and its pastime`.

## T3 — Nina's trip, her wet paws, the fall (the core)

Files: edit `office/kit/sim.ts`, `office/kit/tiles/cat-corner.ts`, `office/kit/voices.ts`; test new `office/test/bathroom-trip.test.ts`.

Edits, in order:

1. `sim.ts` `CatPlan`: add `bath?: { rim: Pt; floor: Pt }`. `Cat`: add `wet: number` (init `0` in the constructor) and `fell: boolean` (init `false`) and `errand.kind` gains `"drink"`.
2. `sim.ts` Sim: `protected prints: Print[] = []` and `pawprints(): readonly Print[] { return this.prints }`.
3. `cat-corner.ts` `cat()`: `bath: { rim: RIM, floor: RIM_FLOOR }`; `via(p)`: add `p.x === RIM.x && p.y === RIM.y ? RIM_FLOOR : …` (first clause); `door(from, to)`: add a `"bath"` room — `roomOf` returns `"bath"` when the point is inside `BATH`, checked first — with `out.bath = [{x: DOOR.x, y: DOOR.y - 3}, {x: DOOR.x, y: HALL - 3}]` and `into.bath = [{x: DOOR.x, y: HALL - 3}, {x: DOOR.x, y: DOOR.y - 3}]`. The existing `a === b` early return covers bath→bath.
4. `sim.ts` `catDo`: union gains `"drink"`: `if (what === "drink") return this.catDrink()`; add

```ts
/** Nina goes to the tub for a drink: through the door, up on the rim; false when the room has no bathroom */
private catDrink(): boolean {
  const c = this.cat, p = this.plan.cat
  if (!p.bath) return false
  const to = p.bath.rim, down = c.mode === "zoom" ? null : p.via(c), up = p.via(to)
  c.path = [...(down ? [down] : []), ...p.door(down ?? c, up ?? to), ...(up ? [up] : []), { ...to }]
  c.mode = "walk"; c.until = this.tick + 150; c.errand = { name: "", kind: "drink" }
  return true
}
```

5. `stepCat`, arrival branch (`if (!c.path.length && c.errand)`): the existing code does `const { name, kind } = c.errand, host = this.actors.get(name)` — add before the host lines:

```ts
if (kind === "drink") {
  c.errand = null; c.mode = "sit"; c.until = this.tick + DRINK
  c.fell = Math.random() < FALL_ODDS
  c.wet = this.tick + DRINK + (c.fell ? FALL_WET : WET)
  this.catSay(this.line("Nina", c.fell ? "splash" : "drink", c.fell ? NINA.splash : NINA.drink), 70)
  return true
}
```

6. `stepCat`, step movement: after `c.x += …; c.y += …` add the trail:

```ts
if (this.tick < c.wet && (c.travelled = (c.travelled ?? 0) + 1) % STRIDE === 0) this.prints.push(layPrint(c.x, c.y, this.tick, c.fell))
```

(Nina moves one pixel per two ticks; `travelled` counts pixels so a print is laid every `STRIDE` px, whatever the tick parity. Add `travelled: number` to `Cat`, init `0`.) When `this.tick >= c.wet` and `c.fell`, reset `c.fell = false` once she is dry.
7. `sim.ts` `step`: after `stepCat()`, `if (this.prints.length) { const n = this.prints.length; this.prints = prune(this.prints, this.tick); if (this.prints.length !== n) changed = true }`.
8. Trigger in the idle decision, right after the `leaps` line and before `const cold`: 

```ts
if (p.bath && r > 0.95 && r <= 0.97 && c.mode !== "sleep" && this.catDrink()) return true
```

   No draw is added; a seeded sequence is the same unless an idle roll lands in that 2 % slice (the keyboard branch needs `r > 0.97`, so it keeps its slice).
9. `voices.ts`: `NINA.drink: ["Tap water. The only honest water.", "Running water is for royalty. I am royalty.", "The tub is a fountain. Mine."]`, `NINA.splash: ["I MEANT to do that.", "Nobody saw that. NOBODY.", "The tub was rude. I will not be discussing it."]`.

Test first (`test/bathroom-trip.test.ts`) — red before steps 1–9:

```ts
import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { BATH, DOOR, FALL_LIFE, LIFE, RIM } from "../kit/bathroom"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

const inside = (r: WideRoom) => r as unknown as { cat: { x: number; y: number; mode: string; wet: number; fell: boolean; path: unknown[] }; tick: number; prints: { x: number; y: number; at: number; until: number }[] }

/** run a trip from the start (boss's own catDo, no waiting on chance): the cat's tile at every tick */
function trip(seed: number, fall: boolean) {
  return seeded(seed, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = inside(room)
    for (let i = 0; i < 20; i++) room.step(a)
    const real = Math.random
    expect(room.catDo("drink")).toBe(true)
    const tiles: [number, number][] = []
    for (let i = 0; i < 2_000; i++) {
      // the fall is the one draw taken at the tub: pin it so the contract is the branch, not luck
      if (r.cat.x === RIM.x && r.cat.y === RIM.y && r.cat.mode !== "sit") Math.random = () => (fall ? 0 : 0.999)
      room.step(a)
      Math.random = real
      const last = tiles[tiles.length - 1]
      if (!last || last[0] !== r.cat.x || last[1] !== r.cat.y) tiles.push([r.cat.x, r.cat.y])
    }
    return { tiles, prints: r.prints.map((p) => ({ ...p })), fell: r.cat.fell }
  })
}

describe("Nina's drinking trip", () => {
  test("she goes in by the door, up on the rim, and the way is the same every run", () => {
    const t = trip(7, false)
    expect(trip(7, false).tiles).toEqual(t.tiles)
    const doorStep = t.tiles.findIndex(([x, y]) => x === DOOR.x && y === DOOR.y - 3)
    const rimStep = t.tiles.findIndex(([x, y]) => x === RIM.x && y === RIM.y)
    expect(doorStep).toBeGreaterThan(-1)
    expect(rimStep).toBeGreaterThan(doorStep)
    for (const [x, y] of t.tiles.slice(doorStep, rimStep + 1)) { expect(x).toBeGreaterThanOrEqual(BATH.x); expect(x).toBeLessThan(BATH.x + BATH.w) ; expect(y).toBeLessThan(BATH.y + BATH.h) }
  })

  test("leaving, every print is laid at its tick and fades LIFE ticks later, exactly", () => {
    const t = trip(7, false)
    expect(t.fell).toBe(false)
    expect(t.prints.length).toBeGreaterThan(0)
    for (const p of t.prints) expect(p.until - p.at).toBe(LIFE)
    // PIN: replace with the literals from the first green run — the contract
    expect(t.prints.map((p) => [p.x, p.y, p.at, p.until])).toEqual([/* [x, y, at, until], … */])
  })

  test("when she falls in the trail is longer and each print lasts longer", () => {
    const ok = trip(7, false), fell = trip(7, true)
    expect(fell.fell).toBe(true)
    expect(fell.prints.length).toBeGreaterThan(ok.prints.length)
    for (const p of fell.prints) expect(p.until - p.at).toBe(FALL_LIFE)
  })

  test("the prints are gone a LIFE after the last was laid", () => seeded(7, () => {
    const room = new WideRoom(696), a = viewOf(office(2), 1), r = inside(room)
    for (let i = 0; i < 20; i++) room.step(a)
    room.catDo("drink")
    for (let i = 0; i < 2_000 && !(r.cat.wet > 0 && r.tick > r.cat.wet); i++) room.step(a)
    const last = Math.max(...r.prints.map((p) => p.until))
    while (r.tick < last) room.step(a)
    expect(r.prints).toHaveLength(0)
  }))
})
```

Run once to get the print literals, check they look right (the first print sits near the door, spacing ~`STRIDE` px, `at` strictly increasing, each `until = at + 600`), paste them into the `toEqual([...])`, commit. A literal that "looks wrong" is a finding, not a number to paste.

Done: `bun test test/bathroom-trip.test.ts test/wide.test.ts test/pets.test.ts test/sim.test.ts` green. Commit: `office: Nina drinks from the tub, leaves wet pawprints, sometimes falls in`.

## T4 — Argos sniffs the trail

Files: edit `office/kit/pets.ts`, `office/rooms/wide.ts` (the `stepDog` ctx); test in `office/test/pets.test.ts`.

Test first (append to `test/pets.test.ts`; uses its `office`, `chance`, `Pets`):

```ts
describe("Argos and the trail", () => {
  test("he follows the prints in the order she laid them, creeping, then sits at the end", () => chance(0, () => {
    const room = new WideRoom(696), a = viewOf(office({ thinking: false }), 1)
    const r = room as unknown as { dog: { x: number; y: number; path: { x: number; y: number }[]; mode: string; creep: boolean; until: number; fuss: unknown }; prints: { x: number; y: number; at: number; until: number }[]; tick: number }
    for (let i = 0; i < 10; i++) room.step(a)
    r.prints = [{ x: 300, y: 188, at: 0, until: 9999 }, { x: 312, y: 188, at: 12, until: 9999 }, { x: 324, y: 188, at: 24, until: 9999 }]
    r.dog.until = 0; r.dog.mode = "sit"; r.dog.fuss = null
    for (let i = 0; i < 40 && !r.dog.creep; i++) room.step(a)
    expect(r.dog.creep).toBe(true)
    expect(r.dog.path.slice(-3).map((p) => [p.x, p.y])).toEqual([[300, 188], [312, 188], [324, 188]])
  }))
  test("with no prints he does what he did before", () => chance(0, () => {
    const room = new WideRoom(696), r = room as unknown as { dog: { creep: boolean }; prints: unknown[] }
    for (let i = 0; i < 400; i++) room.step(viewOf(office({ thinking: false }), 1))
    expect(r.prints).toHaveLength(0)
    expect(r.dog.creep).toBe(false)
  }))
})
```

(`chance(0)` makes every roll fire; first test reaches the trail branch because it is checked before the generic roll in `stepDog`. If the existing `Math.random() < 0.0015`-style gates make `chance(0)` take an earlier branch, order the new branch ahead of it, behind `ctx.antic`.)

Code (`kit/pets.ts`): `stepDog` ctx gains `prints(): readonly { x: number; y: number }[]`. In the idle branch, just after `if (ctx.tick < d.until) return …` and before the roll `r`:

```ts
const trail = ctx.prints()
if (trail.length >= 2 && d.mode !== "sleep" && !d.fuss && Math.random() < 0.01) {
  const first = trail[0]!
  const to: Spot = { x: first.x, y: first.y, aisle: first.y, pose: "stand", face: "left", kind: "roam" }
  d.path = [{ x: d.x, y: d.aisle }, ...ctx.route(d.x, d.aisle, to), ...trail.slice(1).map((p) => ({ x: p.x, y: p.y }))]
  d.aisle = trail[trail.length - 1]!.y; d.mode = "walk"; d.host = null; d.creep = true
  return true
}
```

and clear `d.creep = false` when `d.path` empties (`if (!d.path.length) { d.creep = false; … }` in the arrival block — check where `creep` is already reset and reuse it, don't add a second reset). `rooms/wide.ts` `stepDog()` ctx: `prints: () => this.prints`.

Gotcha: his route to the first print goes through `ctx.route`, which keeps him off furniture; the trail itself is Nina's own path (already walkable). `test/wide.test.ts:239` asserts the dog is never inside a block over a long run — add `chance`-free: extend nothing, just run it.

Done: `bun test test/pets.test.ts test/wide.test.ts`. Commit: `office: Argos follows Nina's wet trail`.

## T5 — draw the prints (the floor decal)

Files: edit `office/rooms/wide.ts` (`render`), `office/kit/draw.ts` only if a helper is needed; test in `office/test/bathroom.test.ts`.

Test first: render the room at a fixed hour with a hand-set `prints` and assert pixel change and that a faded print differs from a fresh one:

```ts
test("a fresh print is drawn, a faded one is fainter, a gone one is not drawn", () => {
  const room = new WideRoom(696), a = viewOf(office(2), 1) // office from ./golden
  const r = room as unknown as { prints: Print[]; tick: number }
  for (let i = 0; i < 5; i++) room.step(a)
  const base = frame(room, a)
  r.prints = [{ x: 200, y: 188, at: r.tick, until: r.tick + LIFE }]
  const fresh = frame(room, a)
  r.prints = [{ x: 200, y: 188, at: r.tick - LIFE + 1, until: r.tick + 1 }]
  const faded = frame(room, a)
  r.prints = []
  expect(fresh).not.toBe(base)
  expect(faded).not.toBe(fresh)
  expect(frame(room, a)).toBe(base)
})
```

(`frame` = `createHash` of `room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0)).rgba`, as `test/golden.ts` does.)

Code: in `WideRoom.render`, right after the hall runner is drawn (`px(0, HALL - 6, …)` line ~334) and before any `sc.item` — floor decals sit under everyone:

```ts
for (const p of this.pawprints()) {
  const s = fadeStage(p, this.tick)
  if (s === 3) continue
  const ink = tint(ROLE.inactive, ROLE.ground, [0.9, 0.6, 0.35][s]!)
  px(p.x - 1, p.y, 2, 2, ink); px(p.x - 2, p.y - 2, 1, 1, ink); px(p.x, p.y - 3, 1, 1, ink); px(p.x + 1, p.y - 2, 1, 1, ink) // pad and three toes
}
```

(`px`, `tint`, `ROLE` are already in scope there; keep the decal 4×4 so it reads at TUI zoom — WCAG test is for text, not decals.) Prints inside the bathroom are drawn by the same loop; the tile's own floor must therefore be drawn **before** this loop — draw the tile floor in the same earlier block as the other zone carpets (`px(0, BAND, OFF_W, …)`), not in `sc.item`. If T2 put the floor in `sc.item`, move just the floor fill.

Done: `bun test test/bathroom.test.ts`. Commit: `office: draw the fading pawprints`.

## T6 — wiring: Nina's card key, a sandbox way to see it, the goldens, the docs

Files: edit `office/tui/main.ts` (one line, ~1382), `office/AGENTS.md`, `office/test/golden.json` (generated).

- `tui/main.ts`, beside `{ key: "s", label: "go have a nap", … }` in Nina's card: `{ key: "b", label: "a drink from the tub", run: doIt(() => r.catDo("drink")) }`. First `grep -n 'key: "b"' tui/main.ts` in that card's list; if taken pick the next free letter. This is the human's one way to see the trip on demand (and the only line that overlaps #242 — keep it a single added line).
- Test: if `test/tui.test.ts` lists the card's keys, add `b`; otherwise the T3 `catDo("drink")` test already covers the action.
- `office/AGENTS.md`: in the `rooms/`/`kit/` prose add one sentence — the bathroom tile (`kit/tiles/bathroom.ts`, `kit/bathroom.ts`), the `bathroom` pastime, Nina's drinking trip leaves `Sim.prints` that fade with the tick, Argos follows them. Same commit as the code (repo law: docs in sync).
- Goldens: `mise run office:golden`, then `git diff --stat office/test/golden.json` must show all five widths changed (the room has a new box at every width). Commit it separately: `office: re-hash the wide room's golden frames for the bathroom`.

Done: `mise run office:check` green (install, typecheck, tests) — run with `OFFICE_TEST_HOUR=3` and `=15` as the checks queue does; and **look at it**: `mise run office:run -- --sandbox`, select Nina, `b`; confirm the door opens, she sits on the rim, leaves prints along the hall that fade over ~a minute, Argos creeps along them. A frame change is seen, not assumed (`office/AGENTS.md` Verify).

## Risks

- **Seeded tests that shift.** The extra pastime changes `plan.lounge` length, so seeded idle picks move; goldens re-hash (T6) but a hand-pinned assertion in `pastimes.test.ts`/`wide.test.ts` may too. Fix by re-deriving what it asserts, never by loosening a bound.
- **Routes through the bath walls.** Guarded by T2's wall test and `wide.test.ts`'s route walk; if Nina's diagonal steps clip a wall corner, add waypoints to `door()`, not gaps to the walls.
- **#242 conflict** is `tui/main.ts` only (T6, one line). Rebase after #242 lands; don't merge it in.
- Out of scope (named, not built): the door animating for the hall's other traffic, coworkers using the toilet, prints from Argos, `home.json` placement of the tile (step 3 of build mode applies `at`).
