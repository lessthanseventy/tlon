# Toy step 5: the events — plan

Spec: `work/toy-step-5-the-events-zoo-meteor-fire-dr/spec.md` (design §3, §8 step 5; ticket #56).
Check: **each plays and tidies itself; none touches a thread or a turn.** Plan only — no code in this commit.
All work is in `office/` (no server). One task = one commit, in order. Every task ends green on
`mise run office:test` for its own file, and the last on `mise run check`.

## Facts this plan rests on (read from the worktree @ 824e31b)

- `Sim.play(kind)` (`kit/sim.ts:460`) is the stand-in: `"event"` = everyone `!` + "Did anyone else hear that?".
  `"drill"` = same + `drillUntil = tick + DRILL`. `ring()` (`:497`) is the precedent for "returns false when
  there is no `plan.door` / nobody there / queue full". The rail room has no `plan.door` (`rooms/rail.ts`).
- The goal chain in `step()` (`kit/sim.ts:~690-705`) is: panicking → alarmed → leaving → caller → queue → visit →
  note → **thinking/stretch/warm ⇒ `home`** → idle. A new event goal goes **after** the thinking/warm lines'
  guard — i.e. only applied to a non-thinking actor — which is exactly spec decision 3 for free.
- `Sim.step` draws `Math.random()` per actor per tick in the idle path; **the event layer must add none**
  (golden frames, `bathroom-trip.test.ts`). The only draw is `pickEvent` at start when no kind is given.
- Door geometry: `plan.door` is the answerer's spot (x = w-18, y = hall row); a visitor stands at
  `(door.x + 12, door.y)` (`Sim.visitor()`); `plan.exit` is 3 px from the right edge. Sheriff = `SHERIFF`
  (`"scharlach"`, `kit/scharlach.ts:9`). Windows are `plan.lounge` spots of `kind: "window"`.
- Drawing: props go through `sc.item(baseY, fn)` + `sc.blit(rows, x, y, {char: colour})` like `drawVisitor`
  (`kit/door.ts`). The floor's light is `WideRoom.nightfall` (`rooms/wide.ts:~455`).
- `Sim.event` in the spec is both a field and a call; here the **method** is `Sim.event(kind?)` and the state is
  `private running`, read through `Sim.eventNow(): {kind, since, t} | null`.

## Decisions (flag if you disagree)

1. **Props are a pure function of `(kind, t, geometry)`** (`propsAt`), so "tidy" is just `running = null` —
   nothing to clean up, no per-prop state to leak. Actor-attached props (the candle, the net) are added by
   `Sim.props()` from the cast's live position.
2. **The cast is fixed at start**: `idle` = non-thinking, non-leaving actors sorted by name, minus the sheriff;
   `sheriff` = `scharlach` if present and non-thinking. Sorted, not drawn → deterministic under any seed.
   A seat that starts a turn mid-event is simply not in `idle` for goals (the goal chain's thinking guard wins).
3. **Lengths**: zoo 1200, meteor 700, power 700, drill 600 (= `DRILL`, asserted), duck **500** — the spec's
   "600–1200" and its duck "~500" disagree; the duck's own number wins, the test bounds are 500–1200.
4. **Blackout and flicker live in `nightfall`**, not a new overlay pass: it already owns the dim + lamp pools.
   Screens already dim there at night; if `draw.ts`'s monitor glow (`:16`) is cheap to re-apply after the dim
   during a blackout, do it; if not, say so in the PR — it is polish, not the check.
5. **`play("event")` stays** as the sandbox/TUI entry (`tui/main.ts:1803`) and now calls `this.event()`, falling
   back to the old `!` stand-in when `event()` returns false (rail room), so the `e` key never feels dead.

## Task 1 — `kit/events.ts`: the table, pure  *(no Sim change)*

Files: `office/kit/events.ts` (new), `office/test/events.test.ts` (new).

Test first:

```ts
import { describe, expect, test } from "bun:test"
import { EVENT_KINDS, EVENTS, pickEvent, propsAt, blackoutAt, flickerAt, type Geo } from "../kit/events"
import { DRILL } from "../kit/sim"

const geo: Geo = { doorX: 600, hallY: 190, ceilY: 12, leftX: 60, windowX: 200, cork: { x: 400, y: 40 } }

describe("the events table", () => {
  test("five kinds, each a bounded script whose beats fall inside it", () => {
    expect(EVENT_KINDS).toEqual(["drill", "zoo", "meteor", "power", "duck"])
    for (const k of EVENT_KINDS) {
      const s = EVENTS[k]
      expect(s.ticks).toBeGreaterThanOrEqual(500)
      expect(s.ticks).toBeLessThanOrEqual(1200)
      for (const b of s.beats) expect(b.at).toBeGreaterThanOrEqual(0), expect(b.at).toBeLessThan(s.ticks)
    }
    expect(EVENTS.drill.ticks).toBe(DRILL)
  })
  test("pickEvent never repeats the last and is a function of the roll", () => {
    for (const last of EVENT_KINDS) for (const r of [0, 0.3, 0.99]) expect(pickEvent(r, last)).not.toBe(last)
    expect(pickEvent(0.5, null)).toBe(pickEvent(0.5, null))
  })
  test("props are empty before the start's beat and after the end; pure in t", () => {
    for (const k of EVENT_KINDS) {
      expect(propsAt(k, EVENTS[k].ticks, geo)).toEqual([])
      expect(propsAt(k, 100, geo)).toEqual(propsAt(k, 100, geo))
    }
    expect(propsAt("duck", 250, geo).map((p) => p.kind)).toEqual(["duck"])
    expect(propsAt("drill", 100, geo)).toEqual([])
  })
  test("only the power cut blacks out; only the meteor flickers", () => {
    expect(blackoutAt("power", 300)).toBe(true)
    expect(blackoutAt("power", EVENTS.power.ticks - 1)).toBe(false) // the lamps are back for the applause
    expect(blackoutAt("meteor", 300)).toBe(false)
    expect(flickerAt("meteor", 0)).toBeNull()
    expect(typeof flickerAt("meteor", 90)).toBe("boolean")
    expect(flickerAt("zoo", 90)).toBeNull()
  })
})
```

Code (`office/kit/events.ts`; scenes' choreography is filled in by tasks 4–7 — task 1 ships duck + empty
bodies for the rest so the table test is green and each later task only fills one `case`):

```ts
// The toy's scripted happenings (design §3): a table of scripts and the pure props each draws. Sim runs
// one at a time (`Sim.event`); nothing here reads a snapshot, a thread or the db — an event is the room's own.
import type { Pt } from "./sim"

export type EventKind = "drill" | "zoo" | "meteor" | "power" | "duck"
export const EVENT_KINDS: EventKind[] = ["drill", "zoo", "meteor", "power", "duck"]

/** a line or a glyph at tick `at` of the event, for `who`: the sheriff, the first idle coworker, or everyone idle */
export type Beat = { at: number; who: "sheriff" | "first" | "idle"; say?: string; emote?: string }
export type Script = { ticks: number; beats: Beat[] }

export const EVENTS: Record<EventKind, Script> = {
  drill: { ticks: 600, beats: [{ at: 0, who: "sheriff", say: "Fire drill! Everyone out!" }] },
  zoo: { ticks: 1200, beats: [] },
  meteor: { ticks: 700, beats: [] },
  power: { ticks: 700, beats: [] },
  duck: { ticks: 500, beats: [{ at: 200, who: "idle", emote: "?" }] },
}

/** where the scenes happen, in room pixels; a room that has no door has no geometry and no events */
export type Geo = { doorX: number; hallY: number; ceilY: number; leftX: number; windowX: number; cork?: Pt }

export type PropKind = "van" | "monkey" | "penguin" | "goat" | "duck" | "streak" | "puff" | "crater"
export type Prop = { kind: PropKind; x: number; y: number; flip?: boolean; step?: number }

/** a roll in [0, 1) → a kind that is not `last` */
export function pickEvent(roll: number, last: EventKind | null): EventKind {
  const from = EVENT_KINDS.filter((k) => k !== last)
  return from[Math.min(from.length - 1, Math.floor(roll * from.length))]!
}

const lerp = (a: number, b: number, t: number) => Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))

/** what is on the stage at tick `t` of `kind` — pure; `[]` outside the event */
export function propsAt(kind: EventKind, t: number, g: Geo): Prop[] {
  if (t < 0 || t >= EVENTS[kind].ticks) return []
  switch (kind) {
    case "duck": {
      // in at the door (0-120), across the hall (120-300), a look round (300-380), back out (380-500)
      const x = t < 120 ? lerp(g.doorX, g.doorX - 30, t / 120) : t < 300 ? lerp(g.doorX - 30, g.leftX + 80, (t - 120) / 180)
        : t < 380 ? g.leftX + 80 : lerp(g.leftX + 80, g.doorX, (t - 380) / 120)
      const flip = t >= 380 || (t >= 300 && Math.floor((t - 300) / 20) % 2 === 1)
      return [{ kind: "duck", x, y: g.hallY, flip, step: Math.floor(t / 6) % 2 }]
    }
    default: return []
  }
}

/** the power cut: lamps out from its 100th tick until the last 60 */
export const blackoutAt = (kind: EventKind, t: number): boolean => kind === "power" && t >= 100 && t < EVENTS.power.ticks - 60

/** the meteor's flicker: null when it isn't one; else alternately lit / unlit every 8 ticks between 60 and 140 */
export const flickerAt = (kind: EventKind, t: number): boolean | null => (kind === "meteor" && t >= 60 && t < 140 ? Math.floor((t - 60) / 8) % 2 === 0 : null)
```

Done: `cd office && bun test test/events.test.ts` → 4 pass. Commit: `office: kit/events.ts — the toy's event table (pure)`.

## Task 2 — `Sim.event()`: start, run, tidy, refuse, hook

Files: `office/kit/sim.ts`, `office/test/events.test.ts`.

Tests first (append; `office()`/`seeded` from `./golden`, `viewOf` from `../kit/crew`; the helper makes seat `i`
idle by flipping `thinking`/`warm` false in the snapshot's roster):

```ts
import { WideRoom } from "../rooms/wide"
import { viewOf } from "../kit/crew"
import { office, seeded } from "./golden"

const view = (idle: string[] = []) => {
  const o = office(4)
  o.roster = o.roster.map((r) => (idle.includes(r.agent) ? { ...r, thinking: false, warm: false } : r))
  return viewOf(o, 1)
}
const run = (r: WideRoom, a: ReturnType<typeof view>, n: number) => { for (let i = 0; i < n; i++) r.step(a) }

describe("Sim.event", () => {
  test("each kind starts, runs its length, and leaves nothing on the stage", () => {
    for (const kind of EVENT_KINDS) seeded(3, () => {
      const r = new WideRoom(696), a = view(["w0", "w1"])
      run(r, a, 300) // the cast walks in first
      expect(r.event(kind)).toBe(true)
      expect(r.eventNow()?.kind).toBe(kind)
      run(r, a, EVENTS[kind].ticks + 5)
      expect(r.eventNow()).toBeNull()
      expect(r.props()).toEqual([])
      expect(r.blackout()).toBe(false)
    })
  })
  test("a second request while one runs is refused", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"])
    run(r, a, 300)
    expect(r.event("duck")).toBe(true)
    run(r, a, 10)
    expect(r.event("meteor")).toBe(false)
    expect(r.eventNow()?.kind).toBe("duck")
  }))
  test("a keyless request draws a kind that is not the last", () => seeded(5, () => {
    const r = new WideRoom(696), a = view(["w0"])
    run(r, a, 300)
    r.event("duck"); run(r, a, EVENTS.duck.ticks + 1)
    expect(r.event()).toBe(true)
    expect(r.eventNow()!.kind).not.toBe("duck")
  }))
  test("onEvent fires at the start and at each beat", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"]), seen: string[] = []
    r.onEvent = (kind, beat) => seen.push(`${kind}:${beat?.at ?? "start"}`)
    run(r, a, 300); r.event("duck"); run(r, a, 600)
    expect(seen).toEqual(["duck:start", "duck:200"])
  }))
  test("an event touches nothing the server owns", () => seeded(3, () => {
    const r = new WideRoom(696), a = view(["w0"]), before = structuredClone(a)
    run(r, a, 300); r.event("meteor"); run(r, a, 800)
    expect(a).toEqual(before)
  }))
  test("the rail room starts none", async () => {
    const { RailRoom } = await import("../rooms/rail") // use the class name rooms/rail.ts exports
    const r = new RailRoom(180)
    expect(r.event("duck")).toBe(false)
    expect(r.eventNow()).toBeNull()
  })
})
```

Code in `kit/sim.ts` (imports: `EVENTS, EVENT_KINDS, pickEvent, propsAt, blackoutAt, flickerAt, type Beat, type EventKind, type Geo, type Prop` from `./events`; `SHERIFF` from `./scharlach`):

```ts
  /** fired at an event's start (`beat` null) and at each beat — step 7's cast reacts here; default none */
  onEvent: ((kind: EventKind, beat: Beat | null) => void) | null = null
  private running: { kind: EventKind; since: number; idle: string[]; sheriff: string | null } | null = null
  private lastEvent: EventKind | null = null
  /** where the scenes are staged; a room with no front door has none and starts no event */
  protected eventGeo(): Geo | null {
    const d = this.plan.door
    return d ? { doorX: d.x + 12, hallY: d.y, ceilY: d.y - 100, leftX: Math.min(...this.plan.lounge.map((s) => s.x)), windowX: 0 } : null
  }

  /** start a scripted scene — one at a time, only where there is a door; false when refused. The only entry. */
  event(kind?: EventKind): boolean {
    if (this.running || this.alarmed || !this.eventGeo() || !this.actors.size) return false
    const k = kind ?? pickEvent(Math.random(), this.lastEvent)
    const crew = [...this.actors.values()].filter((x) => !x.leaving && !x.seat.thinking).map((x) => x.seat.agent).sort()
    const sheriff = crew.includes(SHERIFF) ? SHERIFF : null
    this.running = { kind: k, since: this.tick, idle: crew.filter((n) => n !== sheriff), sheriff }
    this.lastEvent = k
    this.onEvent?.(k, null)
    this.beats(0)
    if (k === "drill") this.drillUntil = this.tick + DRILL
    this.changed = true
    return true
  }
  eventNow(): { kind: EventKind; since: number; t: number } | null {
    const r = this.running
    return r ? { kind: r.kind, since: r.since, t: this.tick - r.since } : null
  }
  /** this tick's props: the scene's, plus what rides on an actor (tasks 5–7 add the candle and the net here) */
  props(): Prop[] {
    const r = this.running, g = this.eventGeo()
    return r && g ? propsAt(r.kind, this.tick - r.since, g) : []
  }
  blackout(): boolean { const r = this.running; return !!r && blackoutAt(r.kind, this.tick - r.since) }
  lampFlicker(): boolean | null { const r = this.running; return r ? flickerAt(r.kind, this.tick - r.since) : null }

  private beats(t: number) {
    const r = this.running!
    for (const b of EVENTS[r.kind].beats) {
      if (b.at !== t) continue
      const who = b.who === "sheriff" ? (r.sheriff ? [r.sheriff] : []) : b.who === "first" ? r.idle.slice(0, 1) : r.idle
      for (const n of who) {
        if (b.say) this.say(n, b.say)
        if (b.emote) { const x = this.actors.get(n); if (x) { x.emote = b.emote; x.emoteUntil = this.tick + 60 } }
      }
      this.onEvent?.(r.kind, b)
    }
  }
  private stepEvent() {
    const r = this.running
    if (!r) return
    const t = this.tick - r.since
    if (t >= EVENTS[r.kind].ticks) { this.running = null; this.changed = true; return }
    if (t > 0) this.beats(t)
  }
```

Wire: call `this.stepEvent()` in `step()` right after `this.tick++`. `play("event")` becomes
`if (kind === "event" && this.event()) return` ahead of the stand-in lines. The drill from `Sim.event("drill")`
sets `drillUntil` itself (do **not** also route through `play`); `play("drill")` keeps working untouched and is
**not** recorded as `running` (the `f` key stays the raw drill — spec decision 5).

Override `eventGeo()` in `WideRoom` (`rooms/wide.ts`): `ceilY: BAND + 6`, `cork: { x: F1 - 58 + 26, y: 40 }`, `leftX: L0`
(use the same names `render` destructures from `this.z`).

Done: `bun test test/events.test.ts` all green **and** `bun test test/pastimes.test.ts test/panic.test.ts test/fire.test.ts`
unchanged green. Commit: `office: Sim.event — one scripted scene at a time, tidies itself, refuses a second`.

## Task 3 — a coworker mid-turn stays put; idle ones are the cast

Files: `office/kit/sim.ts`, `office/test/events.test.ts`.

Test first:

```ts
test("a thinking seat never leaves its desk in any event", () => {
  for (const kind of EVENT_KINDS.filter((k) => k !== "drill")) seeded(9, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"]) // w2, w3, hronir, tertius keep thinking
    run(r, a, 300)
    const desk = (n: string) => `${(r as any).actors.get(n).x}:${(r as any).actors.get(n).y}`
    const at = { w2: desk("w2"), hronir: desk("hronir") }
    r.event(kind)
    for (let i = 0; i < EVENTS[kind].ticks; i++) {
      r.step(a)
      expect(desk("w2")).toBe(at.w2); expect(desk("hronir")).toBe(at.hronir)
    }
  })
})
test("the same seed runs the same twice", () => {
  const trace = () => seeded(4, () => {
    const r = new WideRoom(696), a = view(["w0", "w1"]), out: string[] = []
    run(r, a, 300); r.event("meteor")
    for (let i = 0; i < 700; i++) { r.step(a); out.push(JSON.stringify([...(r as any).actors.values()].map((x: any) => [x.x, x.y]))) }
    return out
  })
  expect(trace()).toEqual(trace())
})
```

Code: in `step()`'s goal chain, **after** the `thinking`/`warm ⇒ home` lines and **before** `idleGoal`, add
`else if ((ev = this.eventGoal(k))) goal = ev` (declare `let ev: Spot | null`). `eventGoal` is `null` until a scene
fills a case, so this task alone changes no behaviour; tasks 5 and 7 fill it:

```ts
  /** where the running scene wants this idle coworker, or null to let them idle as usual */
  protected eventGoal(agent: string): Spot | null {
    const r = this.running
    if (!r || !r.idle.includes(agent) && r.sheriff !== agent) return null
    return null // scenes: meteor → the window (task 5), zoo → the sheriff's chase (task 7)
  }
```

Note: because `thinking`/`warm` precede it in the chain, a coworker mid-turn (or warm at their desk) can never be
pulled — the property test pins that.

Done: tests green, `mise run office:golden` produces **no diff** to `test/golden.json`. Commit:
`office: events leave a thinking seat at its desk (goal seam, no scene yet)`.

## Task 4 — the duck (smallest scene; proves the drawing path end to end)

Files: `office/kit/zoo.ts` (new), `office/rooms/wide.ts`, `office/test/events.test.ts`.

Test first (frame-level, like `panic.test.ts`'s `flame()`): the duck's colour appears near the hall mid-scene and
is gone after.

```ts
import { ROLE } from "../kit/palette"
import { focus, measure } from "./golden"
test("the duck is drawn on the hall mid-scene and gone after", () => seeded(2, () => {
  const r = new WideRoom(696) as any, a = view(["w0"]), at = new Date(2026, 9, 9, 15)
  run(r, a, 300)
  const yellow = () => { // count pixels of the duck's body colour in the hall rows
    const fr = r.render(a, focus, measure, at), want = [1, 3, 5].map((i) => parseInt(ROLE.attention.slice(i, i + 2), 16))
    let n = 0
    for (let y = 170; y < fr.height; y++) for (let x = 0; x < fr.width; x++) {
      const i = (y * fr.width + x) * 4
      if (fr.rgba[i] === want[0] && fr.rgba[i + 1] === want[1] && fr.rgba[i + 2] === want[2]) n++
    }
    return n
  }
  const before = yellow()
  r.event("duck"); run(r, a, 200)
  expect(yellow()).toBeGreaterThan(before)
  run(r, a, 400)
  expect(yellow()).toBe(before)
}))
```

(If a visitor/other `ROLE.attention` pixel confounds the count, assert on the difference as above — `before` is
the baseline. Adjust the y-window to `HALL - 14 … HALL + 4` using the exported `HALL`.)

Code — `office/kit/zoo.ts`:

```ts
// The event scenes' small sprites: blit grids like `drawVisitor` (kit/door.ts); art polish is not step 5.
import type { Scene } from "./draw"
import type { Prop, PropKind } from "./events"
import { ROLE } from "./palette"

type Sprite = { rows: string[]; map: Record<string, string>; base?: number }
const SPRITES: Partial<Record<PropKind, Sprite[]>> = {
  duck: [
    { rows: ["..yy....", ".yyyy.o.", "yyyyyooo", ".yyyyy..", "..oo.oo."].slice(0, 5), map: { y: ROLE.attention, o: ROLE.alarm } },
    { rows: ["..yy....", ".yyyy.o.", "yyyyyooo", ".yyyyy..", "...oo.o."], map: { y: ROLE.attention, o: ROLE.alarm } },
  ],
}

/** a prop with its feet at (x, y); `flip` mirrors it to face left */
export function drawProp(sc: Scene, p: Prop) {
  const frames = SPRITES[p.kind]
  if (!frames) return
  const s = frames[(p.step ?? 0) % frames.length]!
  const rows = p.flip ? s.rows.map((r) => [...r].reverse().join("")) : s.rows
  sc.item(p.y + 0.5, () => sc.blit(rows, p.x - (rows[0]!.length >> 1), p.y - rows.length, s.map))
}
```

`rooms/wide.ts`, right after the `drawVisitor(sc, caller…)` line in `render`:
`for (const p of this.props()) drawProp(sc, p)` (+ `import { drawProp } from "../kit/zoo"`).

Done: test green; `mise run office:golden` no diff. Commit: `office: the duck — walks in, looks round, leaves`.

## Task 5 — the meteor

Files: `office/kit/events.ts`, `office/kit/zoo.ts`, `office/kit/sim.ts`, `office/rooms/wide.ts`, `office/test/events.test.ts`.

Test first:

```ts
test("meteor: a streak, a crater that goes with it, idle coworkers at the window, one blames the deploy", () => seeded(6, () => {
  const r = new WideRoom(696) as any, a = view(["w0", "w1"]), said: string[] = []
  const say = r.say.bind(r); r.say = (w: string, t: string | null) => { said.push(`${w}:${t}`); say(w, t) }
  run(r, a, 300); r.event("meteor")
  run(r, a, 120)
  expect(r.props().map((p: any) => p.kind)).toContain("streak")
  run(r, a, 200)
  expect(r.props().map((p: any) => p.kind)).toContain("crater")
  expect(["w0", "w1"].some((n) => r.actors.get(n).spot.kind === "window")).toBe(true)
  expect(said.some((s) => s.endsWith("…was that the deploy?"))).toBe(true)
  run(r, a, 400)
  expect(r.props()).toEqual([])
}))
test("meteor flicker lights and unlights the lamps in turn", () => {
  const seen = new Set<boolean | null>()
  for (let t = 60; t < 140; t++) seen.add(flickerAt("meteor", t))
  expect(seen.has(true) && seen.has(false)).toBe(true)
})
```

Code:
- `EVENTS.meteor.beats = [{ at: 150, who: "first", say: "…was that the deploy?" }, { at: 60, who: "idle", emote: "!" }]`.
- `propsAt` case `"meteor"`: `t 60–140` a `streak` moving from `(winX + 28, 8)` to `(winX + 4, 34)` (window pane, via
  `g.windowX` — add `windowX: number` to `Geo`; `WideRoom.eventGeo` sets it to `M0 + 4`, the first window's x; default 0 for
  the rail); `t 140–end−60` a `puff` at `(g.doorX - 60, g.hallY)` for 20 ticks, then `crater` there until the end.
  Pure, so the crater vanishes with the scene.
- `zoo.ts` sprites: `streak` `["..o","..o",".oo","oo."]` in `ROLE.body`, `puff` `["..p..",".ppp.","ppppp"]` in `ROLE.prose`,
  `crater` `[".....",".kkk.","kkkkk"]` in `ROLE.edge`.
- `Sim.eventGoal`: for `meteor`, an `idle` agent at `t ∈ [80, ticks − 100)` goes to
  `windows[idleIndex % windows.length]` with `windows = this.plan.lounge.filter((s) => s.kind === "window")`
  (none → null). Index by position in `running.idle` — deterministic.
- `WideRoom.nightfall`: replace the head with
  ```ts
  const flick = this.lampFlicker(), black = this.blackout()
  const d = darkness(h)
  if (d === 0 && flick === null && !black) return
  if (d > 0) sc.cv.glow(0, BAND, this.width, WIDE_H - BAND, ROLE.ground, 0.4 * d)
  const lit = black ? 0 : flick === null ? lampsLit(h, sc.lamps.length) : flick ? sc.lamps.length : 0
  sc.lamps.slice(0, lit).forEach(…same pools…)
  ```
  (blackout's own dim is task 6; keep the daytime path byte-identical when nothing runs.)

Done: tests green; golden unchanged. Commit: `office: the meteor — streak, crater, lamps flicker, the window crowd`.

## Task 6 — the power cut

Files: `office/kit/events.ts`, `office/kit/zoo.ts`, `office/kit/sim.ts`, `office/rooms/wide.ts`, `office/test/events.test.ts`.

Test first:

```ts
test("power cut: dark for the middle, a candle by one idle coworker, applause when the lamps return", () => seeded(8, () => {
  const r = new WideRoom(696) as any, a = view(["w0", "w1"]), at = new Date(2026, 9, 9, 15)
  run(r, a, 300); r.event("power")
  run(r, a, 200)
  expect(r.blackout()).toBe(true)
  expect(r.props().some((p: any) => p.kind === "candle")).toBe(true)
  const lit = (d: Date) => r.render(a, focus, measure, d).rgba.reduce((s: number, v: number) => s + v, 0)
  const dim = lit(at)
  run(r, a, EVENTS.power.ticks - 200 - 30)           // inside the last 60: lamps back
  expect(r.blackout()).toBe(false)
  expect(lit(at)).toBeGreaterThan(dim)
  expect([...r.actors.values()].some((x: any) => x.emote === "♪")).toBe(true)
}))
```

Code:
- `EVENTS.power.beats = [{ at: 100, who: "first", say: "Was that the breaker?" }, { at: EVENTS.power.ticks - 60, who: "idle", emote: "♪" }]`
  (write as literal `640` to avoid self-reference; keep the `ticks - 60` relation in the `blackoutAt` test).
- `Prop.kind` gains `"candle"`; `Sim.props()` appends `{ kind: "candle", x: x.x + 4, y: x.y, step: floor(t/4)%2 }` for
  `running.idle[0]` while `blackout()` (actor-attached).
- `zoo.ts`: candle `["..y","..o",".kkk"]`-style 3×4 with a 2-frame flame; draw a small warm pool in `drawProp`
  for `candle` only: `sc.cv.glow(x - 10, y - 8, 20, 10, ROLE.body, 0.35)`.
- `nightfall`: `if (black) sc.cv.glow(0, BAND, this.width, WIDE_H - BAND, ROLE.ground, 0.5)` after the daylight dim,
  so lamps are out and the floor dark. Re-apply monitor glow only if `draw.ts:16`'s function is reusable here (decision 4).

Done: tests green; golden unchanged. Commit: `office: the power cut — blackout, a candle, applause`.

## Task 7 — zoo's open day

Files: `office/kit/events.ts`, `office/kit/zoo.ts`, `office/kit/sim.ts`, `office/rooms/wide.ts`, `office/test/events.test.ts`.

Test first:

```ts
test("zoo: a van, three animals, the note eaten and back, the sheriff gives chase, all gone at the end", () => seeded(10, () => {
  const r = new WideRoom(696) as any, a = view(["w0", "scharlach"]), kinds = new Set<string>(); let eaten = false
  run(r, a, 300); r.event("zoo")
  for (let i = 0; i < EVENTS.zoo.ticks - 1; i++) {
    r.step(a)
    for (const p of r.props()) kinds.add(p.kind)
    if (r.noteHidden()) eaten = true
  }
  for (const k of ["van", "monkey", "penguin", "goat"]) expect(kinds.has(k)).toBe(true)
  expect(eaten).toBe(true)
  run(r, a, 5)
  expect(r.props()).toEqual([])
  expect(r.noteHidden()).toBe(false)
  expect(r.actors.get("scharlach").spot.kind).not.toBe("desk") // he left it to give chase
}))
```

(`scharlach` must be idle in this fixture: `view` flips `thinking` for names passed — add him via the list as shown.)

Code:
- `EVENTS.zoo.beats = [{ at: 0, who: "idle", emote: "!" }, { at: 300, who: "sheriff", say: "Order! ORDER!" }, { at: 600, who: "first", say: "Who let them in?" }]`.
- `propsAt` `"zoo"` (all x on `g`): `van` at `(doorX + 14, hallY)` for t < 1100 (arrives t 0–60, leaves 1100–1200, x slides
  from off-right); `penguin` waddling the hall `(doorX → leftX + 40)` t 60–900 then back to the door by 1100;
  `monkey` on the ceiling row `y = g.ceilY`, x hopping every 10 ticks (`leftX + (floor(t/10) * 17) % 300`) t 60–1000;
  `goat` walks to `g.cork` (x only, y = hallY) t 60–400, `goat` stays at the cork t 400–700 (chewing), walks out t 700–1100.
  Export `noteHidden(t)`: `kind === "zoo" && t >= 450 && t < 700`; `Sim.noteHidden()` wraps it; the corkboard
  draw skips its first note rect while true (`WideRoom.corkboard`, `this.cork.slice(...)` → leave the board's data
  alone — hide by painting the one note's cell with the cork colour, not by mutating `this.cork`).
- `eventGoal` zoo: `r.sheriff === agent` → `{ ...this.plan.exit, x: quant(penguinX, 8), face: "left", pose: "stand", kind: "roam" }`
  for t ∈ [250, 900) (quantised to 8 px so the route recomputes seldom); `Sim.props()` adds a `net` prop at the
  sheriff's `x ± 8` while chasing.
- Pets use existing modes: on start call `this.catDo("zoomies")`? **No** — spec says Nina on the fridge; use
  `this.catDo("come")` only if it exists as a fridge perch; otherwise leave Nina alone and note it. Argos:
  `WideRoom.dogDo("walk")` at t=60 (no new pet code).
- `zoo.ts` sprites: van (14×8, `ZOO` is text via `sc.text("ZOO", …)`), monkey 5×5, penguin 5×7, goat 7×6 (each 2 frames).

Done: tests green; golden unchanged. Commit: `office: zoo's open day — van, monkey, penguin, goat, the sheriff's net`.

## Task 8 — the drill joins the table; sandbox, docs, gate

Files: `office/tui/main.ts`, `office/tui/sandbox.ts` (label only), `office/AGENTS.md`, `office/test/events.test.ts`.

Test first:

```ts
test("Sim.event('drill') is the drill, with the sheriff calling it", () => seeded(12, () => {
  const r = new WideRoom(696) as any, a = view(["scharlach", "w0"]), said: string[] = []
  const say = r.say.bind(r); r.say = (w: string, t: string | null) => { said.push(`${w}:${t}`); say(w, t) }
  run(r, a, 300)
  expect(r.event("drill")).toBe(true)
  expect(r.alarmed).toBe(true)
  expect(said).toContain("scharlach:Fire drill! Everyone out!")
  expect(r.event("duck")).toBe(false) // one at a time, and not during an alarm
  run(r, a, DRILL + 5)
  expect(r.alarmed).toBe(false); expect(r.eventNow()).toBeNull()
}))
```

Code: nothing new in the sim (task 2 already wires `drill`). `tui/main.ts:1803`: `case "e": { const ok = r.event(); status = ok ? "something's up" : "nothing happens"; if (!ok) r.play("event"); break }`
(keep `f` → `play("drill")` and `d` → `play("doorbell")` exactly). `AGENTS.md` (office): one sentence in the `sim.ts`
bullet — events (`kit/events.ts`: `EVENTS` table, `propsAt`; `Sim.event`, `eventNow`, `onEvent`; sandbox `e`; the
event layer reads no snapshot, draws no `Math.random()` per tick) and `tui/sandbox.ts`' `e` is "event".

Done = the gate:
`mise run office:test` green, `mise run office:golden` leaves `office/test/golden.json` untouched (`git diff --exit-code`),
then `mise run check`. Commit: `office: e plays an event; the drill is one of five; docs`.

## Out of scope (named)

Scheduler, frequency, per-event toggles, `whimsy` (step 6 #57); per-seat reactions (step 7 #58 — `onEvent` is the
hook); changing the existing drill's choreography; art polish; any server/snapshot/endpoint work.

## Open, for the builder to flag rather than guess

- Nina "on the fridge" and Argos "delighted" in the zoo: reuse existing `catDo`/`dogDo` modes only; if no mode fits, skip and say so.
- Monitor glow during a blackout (decision 4).
- `Geo.windowX`/`cork` are read from `WideRoom`'s `this.z`; if a width makes the first window not fit, `streak` is skipped, not clamped.
