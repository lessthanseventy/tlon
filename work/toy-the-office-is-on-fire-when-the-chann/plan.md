# Plan — the office is on fire when the channel is down (ticket #83)

## Dependencies (checked against main 7ef8ef6)
- **Does not wait on #56 (events)** — no event machinery exists on main; this is one derived state
  (`!ok`), not a scheduled event. When #56 lands, the fire can be re-homed as an event; not needed now.
- **Does not need #203 (sandbox)** — tests drive `WideRoom.step()` with `{...office(), ok:false}`. For a
  live look, `office:drive` against a stopped scratch server shows it; sandbox would only add a key.
- Room-side only: `office/kit/sim.ts`, `office/kit/floor.ts`, `office/kit/pets.ts`, `office/rooms/wide.ts`. No server change.

## Facts the tasks rely on
- `Sim.step(a)` (kit/sim.ts ~l.374) already substitutes `lastGood` when `!a.ok`, so the crew stays seated; `this.seeded` is true once an ok snapshot was seen.
- Goal choice per actor is the `if/else` chain at sim.ts ~l.440; first branch `actor.leaving → plan.exit`.
- `plan.exit` is `{x:w-3,y:HALL,kind:"exit"}` (kit/floor.ts:39); rail.ts has its own plan (exit only).
- `actor.mug > sc.tick` draws a steaming mug in hand (kit/draw.ts:129).
- `WideRoom.step` calls `super.step(a)`; Argos speaks via `dogSay(this.argos(occasion))`, lines in `ARGOS` (kit/pets.ts).
- Tick = 100 ms. Tests: `bun test` in `office/`; helpers `office()` (test/wcag.test.ts), `viewOf`, `seeded` (test/golden.ts).

## Behaviour (the spec)
1. Fire starts when `!ok` has held `FIRE_GRACE = 100` ticks (10 s, so a restart blip stays quiet) **and** the room has been seeded (a TUI launched against a down channel stays calm). It clears the tick `ok` returns.
2. While it burns: every actor's goal is a **muster** spot outside (by the EXIT, spread out, one each), a mug in hand; Argos trots out too and barks smoke lines now and then; flames + smoke are drawn at the **server closet**.
3. On clear, nothing special: goals fall back to the normal chain, so they walk back to desks/lounge.

## Tasks (one commit each; run `cd office && bun test <file>` then `mise run office:check` before the last)

### T1 — Plan gets `muster` (kit/floor.ts, kit/sim.ts type)
Test first, `office/test/sim.test.ts`:
```ts
test("the floor plan has a muster spot per crew slot, outside by the exit, none sharing a place", () => {
  const p = widePlan(696)
  expect(p.muster!.length).toBeGreaterThanOrEqual(12)
  const keys = new Set(p.muster!.map((s) => `${s.x}:${s.y}`))
  expect(keys.size).toBe(p.muster!.length)
  for (const s of p.muster!) expect(s.kind).toBe("exit")
})
```
Impl: in `Plan` (sim.ts) add `/** where the crew stands during a fire drill; a room without it uses `exit` */ muster?: Spot[]`. In floorPlan (floor.ts) next to `exit:` add
`muster: Array.from({ length: 16 }, (_, i) => ({ x: w - 8 - (i % 4) * 9, y: HALL - 2 - Math.floor(i / 4) * 5, aisle: HALL, pose: "stand" as const, face: "down" as const, kind: "exit" as const }))`
(implementer: confirm these cells are free of `blocks`/furniture; adjust offsets, keep the test). Export `widePlan` import in the test if not already.
Done: test green. Commit "office: the floor plan names a muster place per slot".

### T2 — Sim tracks the fire (kit/sim.ts)
Test first (`office/test/fire.test.ts`, new):
```ts
import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { FIRE_GRACE } from "../kit/sim"
import { office } from "./wcag.test"
const up = () => viewOf(office(), 1)
const down = () => viewOf({ ...office(), ok: false, note: "channel down" }, 1)
const run = (r: WideRoom, f: () => ReturnType<typeof up>, n: number) => { for (let i = 0; i < n; i++) r.step(f()) }

describe("fire drill", () => {
  test("a short blip is not a fire; a held outage is; recovery puts it out", () => {
    const r = new WideRoom(696)
    run(r, up, 20)
    run(r, down, FIRE_GRACE - 5)
    expect(r.onFire).toBe(false)
    run(r, up, 1); run(r, down, FIRE_GRACE - 5)
    expect(r.onFire).toBe(false)          // the blip reset the clock
    run(r, down, 10)
    expect(r.onFire).toBe(true)
    run(r, up, 1)
    expect(r.onFire).toBe(false)
  })
  test("a room that never saw the channel up does not burn", () => {
    const r = new WideRoom(696)
    run(r, down, FIRE_GRACE * 2)
    expect(r.onFire).toBe(false)
  })
})
```
Impl in `Sim`: `export const FIRE_GRACE = 100`; fields `private downSince = -1` and `protected fire = false`; public getter `get onFire() { return this.fire }`. In `step()` right after the `lastGood` lines (use the *incoming* `a.ok`, so capture `const ok = a.ok` before the reassignment):
```ts
if (ok) { this.downSince = -1; this.fire = false }
else {
  if (this.downSince < 0) this.downSince = this.tick
  if (this.seeded && this.tick - this.downSince >= FIRE_GRACE) this.fire = true
}
```
(`this.tick++` happens after those lines — place the block after `this.tick++`.) Set `this.changed = true` on each flip.
Done: `bun test test/fire.test.ts` green. Commit "office: the sim knows when the channel has been down long enough to burn".

### T3 — The crew files out with their coffee (kit/sim.ts)
Test first (append to fire.test.ts):
```ts
test("on fire, everyone ends at a muster spot holding a mug; all distinct; they return after", () => {
  const r = new WideRoom(696)
  run(r, up, 300)
  run(r, down, FIRE_GRACE + 600)
  const actors = [...(r as any).actors.values()]
  expect(actors.length).toBeGreaterThan(0)
  for (const a of actors) { expect(a.spot.kind).toBe("exit"); expect(a.moving).toBe(false); expect(a.mug).toBeGreaterThan((r as any).tick) }
  expect(new Set(actors.map((a: any) => `${a.x}:${a.y}`)).size).toBe(actors.length)
  run(r, up, 900)
  for (const a of (r as any).actors.values()) expect(a.spot.kind).not.toBe("exit")
})
```
Impl: in the goal chain make fire the **first** branch, before `actor.leaving`:
```ts
const muster = plan.muster ?? [plan.exit]
if (this.fire && !actor.leaving) { goal = muster[[...this.actors.keys()].indexOf(k) % muster.length]!; if (actor.mug < this.tick + 100) actor.mug = this.tick + 3000 }
else if (actor.leaving) goal = plan.exit
```
(re-chain the existing `else if`s). Ensure they walk at full speed (existing `walk`) and `actor.until` logic is untouched. Fire start also sets `emote="!"`, `emoteUntil=tick+30` once per actor on the flip tick.
Done: test green. Commit "office: a fire drill sends the crew outside with their coffee".

### T4 — Argos barks at the smoke (kit/pets.ts, rooms/wide.ts)
Test first:
```ts
test("Argos leaves for the muster and barks smoke lines while it burns", () => {
  const r = new WideRoom(696); run(r, up, 300); run(r, down, FIRE_GRACE + 400)
  const d = (r as any).dog
  expect(d.mode).not.toBe("sleep")
  expect(ARGOS.smoke).toContain(d.said)   // if he's mid-line; else loop until said is set within 400 ticks
})
```
(Write the loop form: step up to 600 ticks, collect `dog.said` values, expect some ∈ `ARGOS.smoke`.)
Impl: `ARGOS.smoke = ["SMOKE! Smoke! SMOKE!", "Is it a squirrel? It smells like a squirrel.", "WOOF! The server closet is on fire!", "I have seen Troy burn. This is worse. Bark."]` (kit/pets.ts, keep the `ARGOS` type so `argos("smoke", …)` typechecks). In `WideRoom.step`, after `super.step`: on the tick `fire` first becomes true (track `private wasFire`), `this.dogDo("walk")` is wrong (random roam) — instead set `d.path = this.plan.route(d.x, d.aisle, muster[muster.length-1])`, `d.mode="walk"`, `d.antic`-free; and while `this.fire && this.quiet(d.saidUntil) && Math.random() < 1/40` → `this.dogSay(this.argos("smoke"))`. Also suppress his idle `muse`/`paper` branches while `this.fire`.
Done: test green. Commit "office: Argos barks at the smoke".

### T5 — Flames and smoke at the server closet (rooms/wide.ts + kit/draw.ts)
Test first (`office/test/fire.test.ts`):
```ts
test("the closet fits the floor (no overlap with the pastime rects) and only burns on fire", () => {
  const z = zones(696), c = closet(z)
  for (const r of Object.values(corner(z)).flat()) { const o = Array.isArray(r) ? r : [r]; for (const q of o) expect(c.x + c.w <= q.x || q.x + q.w <= c.x || c.y + c.h <= q.y || q.y + q.h <= c.y).toBe(true) }
})
test("a burning room draws differently from a calm one; a calm one is unchanged", () => {
  const calm = new WideRoom(696), hot = new WideRoom(696)
  run(calm, up, 300); run(hot, up, 300); run(hot, down, FIRE_GRACE + 5)
  const f = (r: WideRoom, a: any) => r.render(a, focus, measure, new Date(2026, 9, 9, 15)).hash ?? JSON.stringify(r.render(a, focus, measure, new Date(2026, 9, 9, 15)))
  expect(f(hot, down())).not.toBe(f(calm, up()))
})
```
(use whatever `frameHashes()`/Frame API test/golden.ts uses to hash a frame; copy it.)
Impl: export `closet(z: Zones): Rect` from wide.ts — a small grey cabinet door labelled `SERVER`, ~12×22, on the back wall/hall in a **free** spot (candidate: `{x: OFF_W + 4, y: HALL - 30, w: 12, h: 24}`; verify against `corner(z)`, desks and `blocks` using the test above and by looking at `office:drive`). Always draw the closed cabinet (so the fire has a source); that changes the golden frames → `mise run office:golden`, commit the new `golden.json`. When `this.fire`: in `render` after the furniture, draw 3 flame columns on the cabinet using `sc.tick` (`Math.floor(sc.tick/3)%3` picks a height; colours `ROLE.alarm` and `ROLE.live`), and 3 smoke pixels rising and fading above it (offset by `sc.tick`); plus a `ROLE.alarm` "FIRE DRILL" label under the existing channel-down text (l.341). Keep a pure helper `drawFire(sc, rect)` in kit/draw.ts.
Done: tests green; `office:golden` regenerated once.
Commit "office: the server closet, and what it does on fire".

### T6 — Docs + live check
- `office/AGENTS.md`: one line under the sim section: fire drill = `Sim.fire` (grace `FIRE_GRACE`, needs a seeded room), `plan.muster`, `closet()`.
- Live check: `mise run office:drive` (see `drive-office` skill) against a scratch server, stop it, wait >10 s, screenshot: crew outside by EXIT, flames on the closet; restart it, crew returns. Paste evidence in the review.
- Gate: `mise run check` (unsandboxed, per memory) green. Commit "docs: office AGENTS names the fire drill".

## Out of scope (YAGNI)
Nina's reaction, the front door, alarm sound, a user key to trigger it (that's sandbox/#203's `f`), config toggle (belongs to whimsy step 6 of the toy design).
