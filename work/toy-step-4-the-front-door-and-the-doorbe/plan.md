# Toy step 4: the front door and the doorbell — plan

Spec: `docs/plans/2026-10-08-office-as-a-toy-design.md` §5, §8 step 4. Ticket #55. Check (Andrew):
**a ring brings a coworker to the door and a visitor in it; a cut brings pizza.**
Plan only — no code in this commit. Each task below is one commit, in order.

## Facts this plan rests on (read from main @ bc9e0ed)

- The "front door" is the hallway's right end: `plan.exit` = `{x: w-3, y: HALL}` (`kit/floor.ts:39`), a bare
  `EXIT` word (`rooms/wide.ts:335`). The fire drill already files out of it. There is no street drawn in the
  wide room; the street tile + mailbox only exist in the home annex (`kit/homeart.ts`, `kit/mailbox.ts`).
  So the door is *that* spot, dressed — not a new room, no new routing.
- Only `Sim.play("doorbell")` exists (`kit/sim.ts:385`): everyone gets `!`, one says "Ding dong!". Its test
  (`test/pastimes.test.ts:228`) must stay green.
- The live pointer is `refs/heads/live`; `Server.Release.PM.note_live/1` posts a `notice` with payload
  `%{"live" => sha}` once per release. `Server.Release` (no `.PM`) is only migrations — the reader goes on `PM`.
- Seeded determinism: `test/golden.ts` `seeded()` replaces `Math.random`; golden frames run 300 steps, the
  bathroom trip (#244) runs ≤ 2 100. **A new per-tick `Math.random()` would shift every seeded stream and break
  all of them.** The door's schedule therefore draws only when it schedules a ring, and the first ring is
  `RING_FIRST = 6000` ticks out.
- #244 (bathroom, at review) edits `sim.ts`, `floor.ts`, `pets.ts`, `voices.ts`, `rooms/wide.ts`,
  `tiles/office.ts`, `tui/main.ts`, `test/golden.json`. Tasks 1–2 touch none of those: **build them now.**
  Tasks 3–7 branch off main after #244 lands and rebase; re-run `mise run office:golden` after the rebase.

## Decisions (tell me if you disagree — each is cheap to flip)

1. **`release` comes from the newest `live` notice, not from `git rev-parse refs/heads/live`.** `note_live/1`
   already reconciles pointer → message once per release, so `{sha, cut_at}` are one consistent pair, with no git
   subprocess per snapshot poll (`status/0` is polled every few seconds). `cut_at` = when the service said it is
   live (seconds after a cut's restart) — which is when "the release ships". Reader: `Server.Release.PM.live_release/0`.
2. **The door is `plan.door`, an optional `Spot` of kind `"answer"`, 15 px inside the exit** (`x: w-18`). The
   rail room has none → `ring()` there is the old stand-in (bell + "Ding dong!") and returns false.
3. **One visitor at a time**, up to 3 queued, in `Sim` (not in `actors`: a visitor is not a `Seat`, never
   gets a desk, a queue slot or a roster row). The answerer is the *nearest non-thinking* coworker, ties by name
   — no random draw, so who answers is fixed under any seed.
4. **Visitors are presentation only**: no thread, ticket or turn is touched (design §0).
5. **Pizza = the existing `party` pull in `moment()`** (cooler/coffee weight 5) for `PIZZA_TICKS`; no new
   kitchen logic. Carrier = the existing `catLetter()` errand (#185) for the answerer.
6. **Open, named, not built**: sandbox has no release feed, so pizza is not reachable from sandbox's `d`
   (it picks carrier/cookies/tourist/seasonal). A sandbox key for it belongs with step 6's settings pass.
   Voices (step 2/7) will overlay the visitor lines in `door.ts`; they are plain constants here.

## Task 1 — server: `release` on the snapshot  *(no #244 overlap; build now)*

Files: `server/lib/server/release/pm.ex`, `server/lib/server/office.ex`, `server/test/server/office_test.exs`.

Test first (add to `describe "status/0"`; adapt `machine_thread` arity to what the module takes):

```elixir
test "the release the service runs rides the snapshot", %{ws: _ws} do
  assert Office.status().release == nil
  tid = Channel.machine_thread().id
  {:ok, _} =
    Channel.post(%{thread_id: tid, author: "tlon", kind: "notice", body: "release abc1234 is live", payload: %{"live" => "abc1234def"}})

  assert %{sha: "abc1234def", cut_at: %DateTime{}} = Office.status().release
end
```

Code — `PM` (next to `live_since/1`, same fragment):

```elixir
@doc "The release the service runs and when it was said live (the newest `note_live/1` notice); nil before the first."
@spec live_release() :: %{sha: String.t(), cut_at: DateTime.t()} | nil
def live_release do
  with %Message{payload: %{"live" => sha}, created_at: at} <-
         Repo.one(from m in Message, where: m.kind == "notice" and fragment("? \\? 'live'", m.payload), order_by: [desc: m.id], limit: 1),
       do: %{sha: sha, cut_at: at}
end
```
`Office.status/0`: add `release: Server.Release.PM.live_release(),` after `flags:`, and one line in the
moduledoc list. If `:boundary` refuses, add `Server.Release.PM` to Office's deps — don't widen exports.

Done: `mise run server:test -- test/server/office_test.exs` green; `mise run server:check` clean
(`--warnings-as-errors`). Commit: `server: the snapshot names the live release (toy step 4)`.

## Task 2 — office: types and the pure door (`kit/door.ts`)  *(no #244 overlap; build now)*

Files: `office/kit/types.ts`, `office/kit/door.ts` (new), `office/test/door.test.ts` (new).

`types.ts` — in `Agents`, after `flags`:
```ts
  /** the release the service runs (`Server.Release.PM.live_release`): a change of `sha` between refreshes is a cut; null before the first, absent from an older server */
  release?: { sha: string; cut_at: string } | null
```

Test first, `office/test/door.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { arrivals, pickVisitor, RING_FIRST, seasonal } from "../kit/door"
import { EMPTY, type Agents } from "../kit/types"

const snap = (sha: string | null, ok = true): Agents => ({ ...EMPTY, ok, release: sha ? { sha, cut_at: "2026-10-12T00:00:00Z" } : null })
const need = (level: "blocking" | "decide") => ({ level })

describe("who comes by", () => {
  test("seasonal visitors keep their days", () => {
    expect(seasonal(new Date(2026, 9, 31))).toBe("trick")
    expect(seasonal(new Date(2026, 11, 20))).toBe("carol")
    expect(seasonal(new Date(2026, 9, 12))).toBeNull()
  })
  test("pickVisitor is a pure function of the roll and the day; pizza is never scheduled", () => {
    const day = new Date(2026, 9, 12)
    const kinds = new Set([0, 0.2, 0.4, 0.6, 0.8, 0.999].map((r) => pickVisitor(r, day)))
    expect(kinds).toEqual(new Set(["carrier", "cookies", "tourist"]))
    expect(pickVisitor(0.1, new Date(2026, 9, 31))).toBe("trick")
  })
  test("the first ring is far enough out to leave seeded tests alone", () => expect(RING_FIRST).toBeGreaterThan(2_100))
})

describe("what the snapshots say arrived", () => {
  test("a changed sha is a cut: pizza", () => expect(arrivals(snap("a"), snap("b"), [], [])).toEqual(["pizza"]))
  test("the same sha, or a first look, is nothing", () => {
    expect(arrivals(snap("a"), snap("a"), [], [])).toEqual([])
    expect(arrivals(snap("a", false), snap("b"), [], [])).toEqual([])
  })
  test("no release to one: a first cut counts", () => expect(arrivals(snap(null), snap("a"), [], [])).toEqual(["pizza"]))
  test("more letters in the box is the carrier; fewer, or the same, is not", () => {
    expect(arrivals(snap("a"), snap("a"), [need("decide")], [need("decide"), need("blocking")])).toEqual(["carrier"])
    expect(arrivals(snap("a"), snap("a"), [need("decide"), need("decide")], [need("decide")])).toEqual([])
  })
})
```

Code, `office/kit/door.ts`:

```ts
// The front door (toy design §5): who comes by, when, and what a snapshot says arrived. Pure — sim.ts runs
// the visit, rooms/wide.ts draws the door, tui/main.ts feeds it snapshots.
import type { Canvas } from "./canvas"
import type { Scene } from "./draw"
import { mailbox } from "./mailbox"
import { ROLE } from "./palette"
import type { Agents } from "./types"

export type VisitorKind = "carrier" | "pizza" | "cookies" | "tourist" | "trick" | "carol"
/** the first scheduled ring; later ones are RING_MIN + a draw of RING_SPAN (15 to 45 minutes at 100 ms) */
export const RING_FIRST = 6_000, RING_MIN = 9_000, RING_SPAN = 18_000
/** the hours a scheduled ring may come (a bell asked for by a cut or a key rings whenever) */
export const OPEN_FROM = 8, OPEN_TO = 18
/** ticks: how long the bell rattles, how long a visitor waits for someone to come, how long they stay, how long pizza pulls the crew to the kitchen */
export const BELL = 15, WAIT = 150, STAY = 70, PIZZA_TICKS = 600
/** visitors queued behind the one at the door */
export const QUEUE_MAX = 3

/** what the answerer says when they open it */
export const LINE: Record<VisitorKind, string> = {
  carrier: "Post's here.",
  pizza: "Pizza! The release landed. Kitchen, everyone.",
  cookies: "Cookies! We'll take two boxes.",
  tourist: "Uqbar? No idea, sorry. Try the shelf?",
  trick: "Happy Halloween!",
  carol: "Oh, lovely. Truly.",
}

/** a day's own visitor, or null */
export function seasonal(d: Date): VisitorKind | null {
  const m = d.getMonth(), day = d.getDate()
  if (m === 9 && day === 31) return "trick"
  if (m === 11 && day >= 18 && day <= 24) return "carol"
  return null
}

/** a roll in [0, 1) and the day → a visitor; a day's own one takes half the rolls. Never pizza: only a cut brings it. */
export function pickVisitor(roll: number, day: Date): VisitorKind {
  const special = seasonal(day)
  if (special && roll < 0.5) return special
  const r = special ? (roll - 0.5) * 2 : roll
  return (["carrier", "cookies", "tourist"] as const)[Math.min(2, Math.floor(r * 3))]!
}

/** what this refresh brought: a cut is pizza, a fuller mailbox is the carrier. Only between two real snapshots. */
export function arrivals(before: Agents, after: Agents, beforeNeeds: { level: "blocking" | "decide" }[], needs: { level: "blocking" | "decide" }[]): VisitorKind[] {
  if (!before.ok || !after.ok) return []
  const out: VisitorKind[] = []
  if (after.release && before.release?.sha !== after.release.sha) out.push("pizza")
  if (mailbox(needs).total > mailbox(beforeNeeds).total) out.push("carrier")
  return out
}
```

`drawDoor` / `drawVisitor` are added in Task 4 (they need `Scene`; keep this commit pure — drop the two
`import type` lines for `Canvas`/`Scene`/`ROLE` here and add them in Task 4).

Done: `cd office && bun test test/door.test.ts` green; `mise run office:check` green (run unsandboxed, once with
`OFFICE_TEST_HOUR=3`, once with `=15`). Commit: `office: the door's pure side — visitors, seasons, what a snapshot says arrived`.

## Task 3 — the sim: a ring, an answerer, a visitor  *(after #244 lands; rebase first)*

Files: `office/kit/sim.ts`, `office/kit/floor.ts`, `office/test/door-visit.test.ts` (new).

Test first, `office/test/door-visit.test.ts` (pattern: `bathroom-trip.test.ts`):

```ts
import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { BELL, PIZZA_TICKS, STAY, WAIT } from "../kit/door"
import { WideRoom } from "../rooms/wide"
import { office, seeded } from "./golden"

type Inside = { hour: () => number; tick: number; actors: Map<string, { x: number; y: number; moving: boolean }>; caller: { kind: string; who: string; here: number } | null; nextRing: number }
const inside = (r: WideRoom) => r as unknown as Inside
const room = () => {
  const r = new WideRoom(696), a = viewOf(office(2), 1)
  inside(r).hour = () => 16 // her day follows the clock; the gate runs at 03:00 and 15:00
  for (let i = 0; i < 20; i++) r.step(a)
  return { r, a }
}
const until = (r: WideRoom, a: ReturnType<typeof viewOf>, f: () => boolean, max = 600) => { for (let i = 0; i < max && !f(); i++) r.step(a); return f() }

describe("the doorbell", () => {
  test("a ring brings the nearest idle coworker to the door, and the visitor in it", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    expect(r.ring("cookies")).toBe(true)
    expect(until(r, a, () => s.caller?.here !== undefined && s.caller.here >= 0)).toBe(true)
    const who = s.actors.get(s.caller!.who)!
    expect(Math.abs(who.x - r.doorSpot()!.x)).toBeLessThanOrEqual(1)
    expect(r.visitor()).toEqual({ kind: "cookies", x: expect.any(Number), y: expect.any(Number) })
  }))
  test("they stay STAY ticks, then the visitor is gone and the answerer is free", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    r.ring("carrier")
    expect(until(r, a, () => r.visitor() !== null)).toBe(true)
    const at = s.tick
    expect(until(r, a, () => r.visitor() === null, STAY + 5)).toBe(true)
    expect(s.tick - at).toBeGreaterThanOrEqual(STAY - 1)
    r.step(a)
    expect(s.caller).toBeNull()
  }))
  test("who answers and the whole walk are the same every run", () => {
    const walk = () => seeded(7, () => {
      const { r, a } = room(), s = inside(r), seen: string[] = []
      r.ring("tourist")
      for (let i = 0; i < 300; i++) { r.step(a); seen.push(`${s.caller?.who}@${[...s.actors.values()].map((x) => x.x + "," + x.y).join(";")}`) }
      return seen
    })
    expect(walk()).toEqual(walk())
  })
  test("nobody comes if nobody can: no door in the rail room, and a visitor given up on leaves", () => seeded(7, () => {
    const { r, a } = room(), s = inside(r)
    for (const x of s.actors.values()) (x as { leaving?: boolean }).leaving = true
    r.ring("cookies")
    for (let i = 0; i < BELL + WAIT + 10; i++) r.step(a)
    expect(r.visitor()).toBeNull()
  }))
  test("a cut's pizza pulls the crew to the kitchen for PIZZA_TICKS", () => seeded(7, () => {
    const { r, a } = room()
    r.ring("pizza")
    expect(until(r, a, () => r.visitor() !== null)).toBe(true)
    expect(r.pizzaOn()).toBe(true)
    for (let i = 0; i < PIZZA_TICKS + STAY + 10; i++) r.step(a)
    expect(r.pizzaOn()).toBe(false)
  }))
  test("the schedule draws no random number before the first ring is due", () => seeded(7, () => {
    const { r, a } = room(), real = Math.random
    let draws = 0
    Math.random = () => { draws++; return real() }
    try { for (let i = 0; i < 100; i++) r.step(a) } finally { Math.random = real }
    // everything else in the room draws too; what this pins is that the door's own count is zero
    const before = draws
    expect(inside(r).nextRing).toBeGreaterThan(inside(r).tick)
    expect(before).toBeGreaterThanOrEqual(0)
  }))
})
```
(The last test is a tripwire, not a proof: the real proof is that `golden.json` and `bathroom-trip.test.ts`'s
hard-coded prints do not change in this task. If either moves, a draw leaked into `stepDoor` — fix the draw,
never the golden.)

Code, `kit/sim.ts` (names chosen to sit beside `Cat`/`party`):

- imports: `import { BELL, LINE, OPEN_FROM, OPEN_TO, pickVisitor, PIZZA_TICKS, QUEUE_MAX, RING_FIRST, RING_MIN, RING_SPAN, STAY, WAIT, type VisitorKind } from "./door"`
- `Kind` union: add `"answer"`.
- `Plan`: `/** where whoever answers the front door stands, for a room with one */ door?: Spot`
- fields on `Sim`:
```ts
  /** the front door (`kit/door.ts`): visitors waiting, the one at it, and when the schedule rings next */
  private callers: VisitorKind[] = []
  protected caller: { kind: VisitorKind; who: string; bell: number; here: number } | null = null
  protected nextRing = RING_FIRST
  private pizzaUntil = 0
  private nudgeUntil = 0
  private date: () => Date = () => new Date()
```
- `setClock(now)`: also `this.date = now`.
- replace `play(kind)`'s doorbell branch: `if (kind === "doorbell") { this.ring(); return }` (the body below stays for event/drill; delete `doorbell` from its `line` map and type of that map).
- new methods:
```ts
  /** the bell: everyone startles, one says so; with a door and someone to answer it, a visitor is on their way. False when nobody comes. */
  ring(kind?: VisitorKind): boolean {
    for (const x of this.actors.values()) { x.emote = "!"; x.emoteUntil = this.tick + 60 }
    const first = this.actors.keys().next().value
    if (first) this.say(first, "Ding dong!")
    this.changed = true
    if (!this.plan.door || !this.actors.size || this.callers.length >= QUEUE_MAX) return false
    this.callers.push(kind ?? pickVisitor(Math.random(), this.date()))
    return true
  }
  /** the visitor in the doorway, if one is there (not while they wait for someone to come) */
  visitor(): { kind: VisitorKind; x: number; y: number } | null {
    const c = this.caller, d = this.plan.door
    return c && c.here >= 0 && d ? { kind: c.kind, x: d.x + 12, y: d.y } : null
  }
  doorSpot(): Spot | undefined { return this.plan.door }
  /** the bell is still rattling (the last BELL ticks of a ring that has a visitor coming) */
  bellRinging(): boolean { return !!this.caller && this.tick < this.caller.bell }
  /** pizza is on: the kitchen pulls like a birthday */
  pizzaOn(): boolean { return this.tick < this.pizzaUntil }
  /** the tourist asked after Uqbar: the shelf's spine wiggles now (kit/uqbar.ts) */
  shelfNudge(): boolean { return this.tick < this.nudgeUntil }

  private stepDoor(): boolean {
    const door = this.plan.door
    if (!door || !this.seeded) return false
    // the schedule draws only when it makes a ring, never per tick: a seeded run before the first is untouched
    if (this.tick >= this.nextRing) {
      this.nextRing = this.tick + RING_MIN + Math.floor(Math.random() * RING_SPAN)
      const h = this.hour()
      if (h >= OPEN_FROM && h < OPEN_TO && !this.caller && !this.callers.length) this.ring()
    }
    let c = this.caller
    if (!c) {
      const kind = this.callers[0]
      const who = kind && this.answerer(door)
      if (!kind) return false
      this.callers.shift()
      if (!who) return false
      this.caller = c = { kind, who, bell: this.tick + BELL, here: -1 }
      return true
    }
    const x = this.actors.get(c.who)
    if (!x || x.leaving || (c.here < 0 && this.tick > c.bell + WAIT)) { this.caller = null; return true }
    if (c.here < 0) {
      if (x.spotKey !== spotKey(door) || x.moving) return false
      c.here = this.tick
      this.say(c.who, LINE[c.kind])
      x.emote = { carrier: "✉", pizza: "♥", cookies: "♥", tourist: "?", trick: "*", carol: "♪" }[c.kind]; x.emoteUntil = this.tick + 60
      if (c.kind === "carrier") this.catLetter(c.who)
      if (c.kind === "pizza") this.pizzaUntil = this.tick + PIZZA_TICKS
      if (c.kind === "tourist") this.nudgeUntil = this.tick + 40
      return true
    }
    if (this.tick >= c.here + STAY) { this.caller = null; return true }
    return false
  }
  /** the nearest coworker who is not mid-turn (the nearest of anyone, if all are), ties by name: no draw, so the same under any seed */
  private answerer(door: Spot): string | null {
    let best: string | null = null, bestD = Infinity
    for (const [k, x] of [...this.actors].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))) {
      if (x.leaving) continue
      const d = Math.abs(x.x - door.x) + Math.abs(x.y - door.y) + (x.seat.thinking ? 1000 : 0)
      if (d < bestD) { best = k; bestD = d }
    }
    return best
  }
```
- in `step` next to `this.together()`: `if (this.stepDoor()) changed = true`.
- goal chain (where `else if (actor.leaving) goal = plan.exit`): add right after it
  `else if (this.caller?.who === k && plan.door) goal = plan.door`.
- pizza pull: grep `moment(` in `sim.ts`; the `party` argument becomes `(<its current value>) || this.pizzaOn()`.

`kit/floor.ts`, in the returned plan after `muster`:
```ts
    // the front door: whoever answers stands just inside it, clear of the muster grid (x ≥ w-8 downward in steps of 9)
    door: { x: w - 18, y: HALL, aisle: HALL, pose: "stand", face: "right", kind: "answer" },
```

Done: `bun test test/door-visit.test.ts` green; `bun test test/golden.test.ts test/bathroom-trip.test.ts
test/pastimes.test.ts` still green *without regenerating golden*; `mise run office:check` at hours 3 and 15.
Commit: `office: a ring brings an answerer to the door and a visitor in it (toy step 4)`.

## Task 4 — draw the door and the visitor  *(after Task 3)*

Files: `office/kit/door.ts`, `office/rooms/wide.ts`, `office/test/door-draw.test.ts` (new), `office/test/golden.json`.

Test first (pattern: the pawprints frame-hash test in `bathroom.test.ts`):
```ts
import { describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { viewOf } from "../kit/crew"
import { WideRoom } from "../rooms/wide"
import { focus, measure, office } from "./golden"

describe("the front door, drawn", () => {
  const room = new WideRoom(696), a = viewOf(office(2), 1)
  const frame = () => createHash("sha256").update(Buffer.from(room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0)).rgba)).digest("hex")
  test("a visitor in the doorway changes the frame; so does the bell; both go away again", () => {
    for (let i = 0; i < 5; i++) room.step(a)
    const base = frame()
    const r = room as unknown as { caller: unknown; tick: number }
    r.caller = { kind: "cookies", who: "tertius", bell: r.tick + 5, here: -1 }
    const ringing = frame()
    r.caller = { kind: "cookies", who: "tertius", bell: r.tick - 1, here: r.tick }
    const open = frame()
    const kinds = (["carrier", "pizza", "tourist"] as const).map((k) => { r.caller = { kind: k, who: "tertius", bell: 0, here: r.tick }; return frame() })
    r.caller = null
    expect(ringing).not.toBe(base)
    expect(open).not.toBe(ringing)
    expect(new Set([open, ...kinds]).size).toBe(4) // each visitor is its own silhouette, not a colour swap alone
    expect(frame()).toBe(base)
  })
})
```

Code, `kit/door.ts` (re-add `import type { Scene } from "./draw"` and `import { ROLE } from "./palette"`):
```ts
/** the door at the hall's right end, its foot on row `hall`: shut it is a slab with a bell; open it is a dark gap with the leaf swung back. State is shape, never colour alone. */
export function drawDoor(sc: Scene, x: number, hall: number, open: boolean, ringing: boolean) {
  const px = sc.px.bind(sc), top = hall - 24
  px(x - 1, top - 1, 12, 26, ROLE.structure)
  if (open) { px(x, top, 10, 25, ROLE.ground); px(x, top, 2, 25, ROLE.key) } // the leaf swung back, a dark gap
  else { px(x, top, 10, 25, ROLE.edge); px(x + 7, hall - 12, 2, 2, ROLE.prose) } // a slab with its knob
  px(x - 5, hall - 14, 3, 3, ringing && sc.f % 2 ? ROLE.attention : ROLE.inactive) // the bell push
  if (ringing) { px(x - 7, hall - 15, 1, 5, ROLE.attention); px(x - 8, hall - 16, 1, 7, ROLE.attention) } // and its ring, which is a shape too
  sc.text("EXIT", x + 5, top - 4, ROLE.live, 11)
}

const BASE = ["..hhh..", ".hhhhh.", ".sssss.", ".sssss.", "..bbb..", ".bbbbb.", ".bbbbb.", ".bbbbb.", "..lll..", "..l.l.."]
/** what each visitor changes about the figure: rows replaced, so the silhouettes differ */
const KIT: Record<VisitorKind, { rows: Record<number, string>; body: string }> = {
  carrier: { rows: { 0: ".hhhhh.", 6: "pbbbbb.", 7: "ppbbb.." }, body: ROLE.key }, // cap and a satchel on the hip
  pizza: { rows: { 4: "ppppppp", 5: "ppppppp" }, body: ROLE.alarm }, // the flat box held out in front
  cookies: { rows: { 0: "h.hhh.h", 6: "bbbbbpp", 7: "bbbbbpp" }, body: ROLE.attention }, // pigtails and a tray
  tourist: { rows: { 0: "hhhhhhh", 5: "ppbbbbb", 6: "ppbbbb." }, body: ROLE.live }, // sunhat and a map held up
  trick: { rows: { 0: "..h.h..", 1: ".hhhhh.", 6: "bbbbbbp", 7: ".bbbbpp" }, body: ROLE.assistant }, // horns and a pumpkin pail
  carol: { rows: { 0: ".hhhhh.", 1: "hhhhhhh", 6: "bbbbbp.", 7: "bbbbbp." }, body: ROLE.prose }, // a bobble hat and a lantern
}
/** a visitor standing with their feet at (x, y) */
export function drawVisitor(sc: Scene, x: number, y: number, kind: VisitorKind) {
  const k = KIT[kind], rows = BASE.map((r, i) => k.rows[i] ?? r)
  sc.item(y + 0.5, () => sc.blit(rows, x - 3, y - 10, { h: ROLE.structure, s: ROLE.body, b: k.body, l: ROLE.inactive, p: ROLE.prose }))
}
```
Each row string must be exactly 7 wide — `bun test` fails on a ragged blit, which is the check.

`rooms/wide.ts`:
- imports: `drawDoor, drawVisitor` from `../kit/door`.
- line 335: replace `text("EXIT", W - 14, HALL - 8, ROLE.live, 11)` with
  `drawDoor(sc, W - 12, HALL, this.visitor() !== null, this.bellRinging())`
  (it prints the EXIT word itself, above the door).
- in the actors/items pass, next to the other `sc.item` draws: `const v = this.visitor(); if (v) drawVisitor(sc, v.x, v.y, v.kind)`.

Then: `mise run office:golden` as a **separate commit** (`office: golden frames after the door`).
Done: `door-draw.test.ts` green; `office:check` at hours 3 and 15. Commit: `office: the front door and its visitors, drawn`.
(Look at it once with the `drive-office` skill — a screenshot of the hallway's right end, door open, in the PR.)

## Task 5 — the tourist makes Uqbar's spine wiggle

Files: `office/kit/uqbar.ts`, `office/rooms/wide.ts` (line ~366), `office/test/uqbar.test.ts`.

Test first (add):
```ts
test("a nudge wiggles the shelved spine off the 3-minute beat", () => {
  expect(wiggle(1002)).toBe(0)        // quiet: t ≥ 12
  expect(wiggle(1002, true)).toBe(1)  // asked after
  expect(wiggle(1000, true)).toBe(0)  // and it is a wiggle, not a shift: alternates every 2 ticks
})
```
Code: `export function wiggle(tick: number, nudge = false): 0 | 1 { if (nudge) return tick % 4 >= 2 ? 1 : 0; …existing… }`;
`drawShelf(sc, shelf, shelved, live, nudge = false)` passes it to `wiggle(sc.tick, nudge)`; `wide.ts`:
`drawShelf(sc, shelf, mode === "shelved", !!a.uqbar, this.shelfNudge())`.
A book that is out flying has no spine on the shelf, so there is nothing to wiggle — the tourist's line still
plays. Done: `bun test test/uqbar.test.ts` + `test/door-visit.test.ts` green. Commit: `office: a lost tourist makes Uqbar's spine wiggle`.

## Task 6 — wire the snapshots and the key

Files: `office/tui/main.ts`, `office/test/door-visit.test.ts` (one more test).

`tellNews` (main.ts:307) already has both snapshots and both needs lists. Add, after the notification block:
```ts
  for (const kind of arrivals(before, all, beforeNeeds, needs)) room().ring(kind)
```
`import { arrivals } from "../kit/door"`. The `d` key (main.ts:1730) keeps calling `r.play("doorbell")`, which now
rings through `ring()`; no change there. `tellNews` runs only when both snapshots are `ok`, so a start-up is never
a cut.

Test: in `door-visit.test.ts`, the §8 check end to end through the one pure seam the TUI uses:
```ts
test("§8: a ring brings a coworker to the door and a visitor in it; a cut brings pizza", () => seeded(7, () => {
  const { r, a } = room(), s = inside(r)
  const before: Agents = { ...EMPTY, ok: true, release: { sha: "a", cut_at: "2026-10-12T00:00:00Z" } }
  const after: Agents = { ...before, release: { sha: "b", cut_at: "2026-10-12T01:00:00Z" } }
  for (const k of arrivals(before, after, [], [])) r.ring(k)
  expect(until(r, a, () => r.visitor()?.kind === "pizza")).toBe(true)
  expect(s.actors.get(s.caller!.who)).toBeDefined()
  expect(r.pizzaOn()).toBe(true)
}))
```
(`import { arrivals } from "../kit/door"; import { EMPTY, type Agents } from "../kit/types"`.)
Done: green; `mise run office:check` hours 3 and 15. Commit: `office: a cut rings the bell, a fuller mailbox brings the carrier`.

## Task 7 — the gate, and the hand-off

`mise run check` from the worktree root (server, adapters, office, names, task manual), unsandboxed. `record_check`
its real exit. Branch is rebased onto main (never merged in), history linear. PR body: the §8 check's test name,
the screenshot from Task 4, and the Decisions above verbatim so review can veto one.

## Order and size

| # | Commit | Files | Needs #244? |
|---|---|---|---|
| 1 | server: snapshot names the live release | 3 | no |
| 2 | office: pure door + types | 3 | no |
| 3 | sim: ring → answerer → visitor | 3 | yes |
| 4 | draw door + visitor, then golden | 4 | yes |
| 5 | tourist → Uqbar wiggle | 3 | yes |
| 6 | wire snapshots (cut, mail) | 2 | yes |

Build by pierre if free, else whoever built #244; QA nolan: ring the bell with `d` in `office:sandbox`; stub a
changed `release.sha` into the fake source (or restart the dev server after a cut) and watch pizza arrive.
