# Toy step 6: the wackiness dial — plan

Ticket #57; design `docs/plans/2026-10-08-office-as-a-toy-design.md` §7, §8 step 6 (+ Andrew's preset ask).
Check: **business plays no event and no banter; rimworld chains events; a dial overridden under a preset holds;
the work (threads, tickets, turns, code) is never touched at any setting.**
Plan only — no code in this commit. All work is in `office/` (no server). One task = one commit, in order; each
ends green on `cd office && bun test test/<its file>`, the last on `mise run check`.

## Facts this plan rests on (read from the worktree @ 22a41af)

- **Nothing fires an event on its own today.** `Sim.event()` (`kit/sim.ts:489`) is called only by the sandbox
  `e` key (`play("event")`, `tui/main.ts:1998`). Doorbell rings are scheduled in `stepDoor()` (`kit/sim.ts:611`,
  `nextRing`, `RING_MIN`/`RING_SPAN` in `kit/door.ts`, 100 ms ticks). So "whimsy off plays nothing" has only the
  door and banter to gate **until Task 3 adds the event scheduler**. Spec's `some` ≈ one a week is only
  meaningful in the real room, so frequency is a mean gap in *in-hours-open ticks*, see Task 1.
- **No `office.json` and no whimsy knob exist** (`grep -ri whimsy office/` → only the events test names).
  The server's `banter` bool (`server/lib/server/operator_config.ex:114`) is machine-wide and server-written;
  the office cannot flip it, so the office gate is *presentation*: it drops banter lines before `room().converse`
  (`tui/main.ts:453-473`) and the canned fallback. Server still spends the tokens — say so in the PR, don't hack it.
- Local prefs live in `CONFIG` (`tui/main.ts:91`: `~/.config/tlon`, a tmp dir in the sandbox) and are read with
  `readFileSync`+`JSON.parse` in try/catch (`main.ts:109,314`). `office.json` goes there, same shape of code.
- The idle path draws `Math.random()` per actor per tick; **the whimsy layer adds none when the answer is "no"**
  (golden frames, `test/golden.ts`, `bathroom-trip.test.ts`). The scheduler draws only when it makes a decision,
  like `nextRing`.
- `EventKind` = `drill|zoo|meteor|power|duck` (`kit/events.ts:5`). Scenes are pure `propsAt(kind,t,geo)`.

## Decisions (flag if you disagree)

1. **State = `{ mode, preset, overrides }`, never a flat copy of dials.** Resolved dials =
   `{...PRESETS[preset], ...overrides}` (event toggles merged key-wise). "Custom" is *derived*
   (`overrides` non-empty); choosing a preset clears overrides; touching a dial writes one override and the card
   shows `casual (custom)`. This is the only shape that makes "a dial overridden under a preset holds" true by
   construction rather than by bookkeeping.
2. **Four presets** per Andrew: `business`, `casual` (default — "some"), `party`, `rimworld`. The old
   `off|some|lots` is dropped (never shipped, nothing to migrate); `off`≈business, `some`≈casual, `lots`≈party.
3. **Dials**: `banter` bool · `frequency` never|rare|some|lots (mean gap) · `severity` 1|2|3 · `chain` bool ·
   `events` per-kind bool · `weirdness` curated|procedural|invented · `pets` bool (false = asleep) ·
   `doorbell` off|normal|busy · `souls` bool (side projects on the corkboard) · `moods` bool (real history sours a
   mood). `mode` (office|sandbox) is *not* a dial and is not touched by a preset.
4. **Business = the room shows work only**: no banter, no events, doorbell off, pets asleep, plain looks
   (`weirdness: "curated"`), no souls, no moods. Voice stays (it is tone, not content) — nothing to gate.
5. **Chaos never reaches the work.** Mood swings read history (a red build) but write only to room state
   (`Actor.emote`/a room-local mood), never to a thread, ticket, turn or the server. A test asserts the
   scheduler/mood code imports nothing from `tui/data` (Task 6).
6. **Severity** scales *how much*, not *what*: meteor crater size, zoo animals count, duck → flock. Pure
   functions of `(kind, t, geo, severity)` so tidy stays `running = null`.
7. **Weirdness, pets and souls gates are narrow switches at one seam each** (listed in the tasks). Where the seam
   is not obvious I say "find with the grep given"; the executor must read it first and report if the seam does
   not exist — **unverified: accessories/invented parts pipeline** (`kit/parts.ts`, `kit/hall.ts`), I did not
   trace which call picks procedural vs invented parts.

## Task 1 — `kit/whimsy.ts`: presets, dials, resolve (pure)

Files: `office/kit/whimsy.ts` (new), `office/test/whimsy.test.ts` (new).

Test first:

```ts
import { describe, expect, test } from "bun:test"
import { DEFAULT, PRESETS, PRESET_IDS, resolve, setPreset, setDial, isCustom, parse, meanGap } from "../kit/whimsy"
import { EVENT_KINDS } from "../kit/events"

describe("whimsy presets", () => {
  test("default is casual, everything on, mode office", () => {
    expect(DEFAULT).toEqual({ mode: "office", preset: "casual", overrides: {} })
    expect(Object.values(resolve(DEFAULT).events).every(Boolean)).toBe(true)
  })
  test("business is silent: no banter, no events, no bell, pets asleep", () => {
    const d = resolve({ ...DEFAULT, preset: "business" })
    expect(d.banter).toBe(false); expect(d.frequency).toBe("never"); expect(d.doorbell).toBe("off")
    expect(d.pets).toBe(false); expect(d.souls).toBe(false); expect(d.chain).toBe(false)
  })
  test("rimworld chains, escalates and sours moods", () => {
    const d = resolve({ ...DEFAULT, preset: "rimworld" })
    expect(d.chain).toBe(true); expect(d.severity).toBe(3); expect(d.moods).toBe(true)
  })
  test("a dial overridden under a preset holds, and shows as custom", () => {
    let s = setDial({ ...DEFAULT, preset: "rimworld" }, "banter", false)
    expect(resolve(s).banter).toBe(false)
    expect(resolve(s).chain).toBe(true)           // the rest of the preset still holds
    expect(isCustom(s)).toBe(true)
    s = setDial(s, "events", { ...resolve(s).events, duck: false })
    expect(resolve(s).events.duck).toBe(false); expect(resolve(s).events.zoo).toBe(true)
  })
  test("choosing a preset sets the dials: it clears every override", () => {
    const s = setPreset(setDial(DEFAULT, "banter", false), "party")
    expect(s.overrides).toEqual({}); expect(isCustom(s)).toBe(false); expect(resolve(s).banter).toBe(true)
  })
  test("an override equal to the preset's value is dropped, so custom un-sticks", () => {
    expect(isCustom(setDial(DEFAULT, "banter", resolve(DEFAULT).banter))).toBe(false)
  })
  test("mean gaps are ordered never > rare > some > lots", () => {
    expect(meanGap("never")).toBe(Infinity)
    expect(meanGap("rare")).toBeGreaterThan(meanGap("some"))
    expect(meanGap("some")).toBeGreaterThan(meanGap("lots"))
  })
  test("parse: junk, a partial file and an unknown preset all fall back to defaults field by field", () => {
    expect(parse("not json")).toEqual(DEFAULT)
    expect(parse(JSON.stringify({ preset: "nope", mode: "sandbox", overrides: { severity: 9, banter: false } })))
      .toEqual({ mode: "sandbox", preset: "casual", overrides: { banter: false } })
    expect(PRESET_IDS).toEqual(["business", "casual", "party", "rimworld"])
    expect(EVENT_KINDS.every((k) => k in resolve(DEFAULT).events)).toBe(true)
  })
})
```

Code (`office/kit/whimsy.ts`):

```ts
// The wackiness dial (toy design §7): one preset over individual dials; an override beats the preset.
// State is {mode, preset, overrides} — "custom" is derived, so a held override can't be lost by bookkeeping.
import { EVENT_KINDS, type EventKind } from "./events"

export type Preset = "business" | "casual" | "party" | "rimworld"
export const PRESET_IDS: Preset[] = ["business", "casual", "party", "rimworld"]
export type Freq = "never" | "rare" | "some" | "lots"
export type Weird = "curated" | "procedural" | "invented"
export type Dials = {
  banter: boolean; frequency: Freq; severity: 1 | 2 | 3; chain: boolean; events: Record<EventKind, boolean>
  weirdness: Weird; pets: boolean; doorbell: "off" | "normal" | "busy"; souls: boolean; moods: boolean
}
export type State = { mode: "office" | "sandbox"; preset: Preset; overrides: Partial<Dials> }

const allOn = Object.fromEntries(EVENT_KINDS.map((k) => [k, true])) as Record<EventKind, boolean>
const allOff = Object.fromEntries(EVENT_KINDS.map((k) => [k, false])) as Record<EventKind, boolean>

export const PRESETS: Record<Preset, Dials> = {
  business: { banter: false, frequency: "never", severity: 1, chain: false, events: allOff, weirdness: "curated", pets: false, doorbell: "off", souls: false, moods: false },
  casual:   { banter: true,  frequency: "some",  severity: 1, chain: false, events: allOn,  weirdness: "curated", pets: true,  doorbell: "normal", souls: false, moods: false },
  party:    { banter: true,  frequency: "lots",  severity: 2, chain: false, events: allOn,  weirdness: "invented", pets: true, doorbell: "busy", souls: true, moods: false },
  rimworld: { banter: true,  frequency: "lots",  severity: 3, chain: true,  events: allOn,  weirdness: "invented", pets: true, doorbell: "busy", souls: true, moods: true },
}
export const DEFAULT: State = { mode: "office", preset: "casual", overrides: {} }

export function resolve(s: State): Dials {
  const b = PRESETS[s.preset], o = s.overrides
  return { ...b, ...o, events: { ...b.events, ...(o.events ?? {}) } }
}
export const isCustom = (s: State) => Object.keys(s.overrides).length > 0
export const setPreset = (s: State, preset: Preset): State => ({ ...s, preset, overrides: {} })
export function setDial<K extends keyof Dials>(s: State, k: K, v: Dials[K]): State {
  const base = PRESETS[s.preset][k], same = JSON.stringify(base) === JSON.stringify(v)
  const { [k]: _gone, ...rest } = s.overrides
  return { ...s, overrides: same ? rest : { ...rest, [k]: v } }
}

/** mean ticks (100 ms) between spontaneous events: rare ≈ a day, some ≈ a week's-ish felt as ~2h open, lots ≈ 20 min */
export const meanGap = (f: Freq): number => ({ never: Infinity, rare: 200_000, some: 72_000, lots: 12_000 })[f]

const isFreq = (x: unknown): x is Freq => x === "never" || x === "rare" || x === "some" || x === "lots"
const isWeird = (x: unknown): x is Weird => x === "curated" || x === "procedural" || x === "invented"
/** office.json text → state; every field falls back to its default on its own */
export function parse(text: string): State {
  let j: any
  try { j = JSON.parse(text) } catch { return DEFAULT }
  if (!j || typeof j !== "object") return DEFAULT
  const o: Partial<Dials> = {}, r = j.overrides ?? {}
  if (typeof r.banter === "boolean") o.banter = r.banter
  if (isFreq(r.frequency)) o.frequency = r.frequency
  if (r.severity === 1 || r.severity === 2 || r.severity === 3) o.severity = r.severity
  if (typeof r.chain === "boolean") o.chain = r.chain
  if (isWeird(r.weirdness)) o.weirdness = r.weirdness
  if (typeof r.pets === "boolean") o.pets = r.pets
  if (r.doorbell === "off" || r.doorbell === "normal" || r.doorbell === "busy") o.doorbell = r.doorbell
  if (typeof r.souls === "boolean") o.souls = r.souls
  if (typeof r.moods === "boolean") o.moods = r.moods
  if (r.events && typeof r.events === "object") {
    const e: Partial<Record<EventKind, boolean>> = {}
    for (const k of EVENT_KINDS) if (typeof r.events[k] === "boolean") e[k] = r.events[k]
    if (Object.keys(e).length) o.events = e as Record<EventKind, boolean>
  }
  return {
    mode: j.mode === "sandbox" ? "sandbox" : "office",
    preset: PRESET_IDS.includes(j.preset) ? j.preset : "casual",
    overrides: o,
  }
}
```

Done: `cd office && bun test test/whimsy.test.ts` → all pass. Commit: `office: kit/whimsy.ts — presets, dials and overrides (pure)`.
Note: `setDial` for `events` stores the whole map as an override; `resolve` merges key-wise so partial files also work.

## Task 2 — `office.json` load/save (`kit/whimsy-file.ts`)

Files: `office/kit/whimsy-file.ts` (new), `office/test/whimsy-file.test.ts` (new).

Test first: `load(path)` of a missing file → `DEFAULT`; `save(path, s)` then `load(path)` round-trips; `save` to an
unwritable dir does not throw (a read-only home just doesn't remember — same stance as `writeState`,
`tui/main.ts:104`); `load` of garbage → `DEFAULT`. Use `mkdtempSync(join(tmpdir(), "whimsy-"))`.

Code:

```ts
import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { DEFAULT, parse, type State } from "./whimsy"

export const load = (path: string): State => { try { return parse(readFileSync(path, "utf8")) } catch { return DEFAULT } }
export function save(path: string, s: State) {
  try { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, JSON.stringify(s, null, 2) + "\n") } catch { /* it just won't remember */ }
}
```

Done: `bun test test/whimsy-file.test.ts`. Commit: `office: office.json — load and save the whimsy state`.

## Task 3 — the Sim honours the dials: events, bell, pets (the gates)

Files: `office/kit/sim.ts`, `office/test/whimsy-sim.test.ts` (new). Read `kit/sim.ts:455-540` and `:611-625` first.

Add to `Sim`: `private dials: Dials = resolve(DEFAULT)`, `setWhimsy(d: Dials)`, and a scheduler `stepEvents()`
called beside `stepDoor()` (`:728`):

```ts
// spontaneous events: a seeded-run's first draw is at the first scheduled gap, never per tick (golden frames)
private nextEvent = -1
private stepEvents(): boolean {
  const gap = meanGap(this.dials.frequency)
  if (!Number.isFinite(gap) || !this.seeded || !this.eventGeo() || this.running || this.alarmed) return false
  if (this.nextEvent < 0) this.nextEvent = this.tick + Math.round(gap * (0.5 + Math.random()))
  if (this.tick < this.nextEvent) return false
  this.nextEvent = this.tick + Math.round(gap * (0.5 + Math.random()))
  const on = EVENT_KINDS.filter((k) => this.dials.events[k])
  if (!on.length) return false
  return this.event(pickEvent(Math.random(), this.lastEvent, on))
}
```

Gates, each one line at its seam:
- `event(kind?)` (`:489`): refuse when `!this.dials.events[k]` **for a keyed `kind` too** — "a toggled-off event
  never plays" is absolute; the sandbox `e` key then reports "that one's switched off" (Task 5 status text).
  `pickEvent` gains an optional third arg `from: EventKind[]` (default all) — extend the `kit/events.ts` test.
- `stepDoor()` (`:615`): `doorbell: "off"` → never schedule a ring (`nextRing = Infinity`; reset on change);
  `"busy"` → `RING_MIN/2`, `RING_SPAN/2`. The keyed `ring()` (sandbox `d`) is **not** gated: the sandbox is the
  operator driving, and the check is about what the room does by itself. State this in a comment.
- pets (`pets: false`): in the cat's mode choice (`~:372`, `c.mode` selection) force `sleep`, and in the Nina/Argos
  chatter paths (`catSay`) return early — a sleeping pet says nothing. Do **not** remove the pet from the room.
- `play("drill")` stays keyed-only; the scheduler never starts `drill` unless `events.drill` is on (it is in `on`).

Test first (`test/whimsy-sim.test.ts`, use `seeded()` from `golden.ts`, a `WideRoom`/`RailRoom`+door fixture as in
`events.test.ts` — copy its setup):

1. `business`: step 200 000 ticks seeded → `eventNow()` never non-null, no `onEvent` call, `ring` never called.
2. `casual` frequency `lots` + `events` only `{duck:true}`: over 100 000 ticks every started event is `duck`;
   `event("zoo")` returns `false` and `eventNow()` stays null.
3. `rimworld` with `doorbell: "off"` override: no ring in 100 000 ticks while events still start (override holds).
4. `pets: false`: the cat's `mode` is `"sleep"` after settling, `catSay` records nothing in 5 000 ticks.
5. Default dials, same seed as before this task: the golden frames in `wide.test.ts` are **unchanged** (no extra draws).

Done: `bun test test/whimsy-sim.test.ts test/events.test.ts test/wide.test.ts test/sim.test.ts` green. Commit:
`office: the Sim honours the whimsy dials — spontaneous events, the bell, the pets`.

## Task 4 — rimworld: chains, severity, moods

Files: `office/kit/events.ts`, `office/kit/sim.ts`, `office/test/whimsy-chain.test.ts` (new).

- `kit/events.ts`: `CHAINS: Record<EventKind, EventKind[]>` — what an event can start:
  `zoo→[drill]`, `drill→[power]`, `power→[duck]` (the penguin panics: the duck stands in for "panics the penguin"
  until step 7 gives the cast reactions), `meteor→[power]`, `duck→[]`. Pure; a test asserts every value is an
  `EventKind`, no self-loops, and the chain `zoo→drill→power` terminates (no cycle: `duck` is a sink).
- `Sim.event()`'s tidy path (where `running = null`): if `dials.chain`, draw once: `Math.random() < 0.6` and the
  successor is `dials.events`-enabled → `this.event(next)` immediately (one at a time still holds because
  `running` was just cleared). Chain depth is capped at 3 (`chainDepth` reset when an event is *not* chained).
- Severity: `propsAt(kind, t, geo, severity = 1)` — meteor: crater size `severity`, extra streaks at 2–3; zoo:
  a second/third animal at 2/3; duck: `severity` ducks staggered 40 ticks. Default 1 returns exactly today's props
  (assert `propsAt(k,t,geo,1)` deep-equals `propsAt(k,t,geo)` for every kind and t∈[0,ticks) step 25).
- Moods (`dials.moods`): on the Sim, `private sour = new Map<string, number>()` (agent → until tick);
  `Sim.sourMood(agent: string, ticks = 36_000)` sets it; while sour, the actor's idle emote pool is the
  `"grumpy"` list (`look.emote` pool at `:835`) and `eventGoal` leaves them out of the cheering. Fed from
  the TUI (Task 5) by a red build; the Sim itself reads no thread.

Test first: with `chain: true`, a seeded run over 100 000 ticks at `lots` shows at least one event whose
`since` equals the previous event's end tick and whose kind is in `CHAINS[prev]`; with `chain: false` never.
`sourMood("x")` under `moods: false` is a no-op (asserted), under `true` changes the emote pool for 36 000 ticks.

Done: `bun test test/whimsy-chain.test.ts test/events.test.ts`. Commit: `office: rimworld — chained events, severity, sour moods`.

## Task 5 — the TUI: wire the state and the settings card

Files: `office/tui/main.ts`, `office/test/whimsy-card.test.ts` (new). Read `tui/main.ts:1413-1440` (the existing
`settings` card, the model for a cycle/bool row list) and `:1982-2000` (the keys).

- Load once at boot: `const OFFICE = join(CONFIG, "office.json"); let whim = load(OFFICE)`. On every change:
  `whim = …; save(OFFICE, whim); for (const r of rooms.values()) r.setWhimsy(resolve(whim))`; also call it when
  a room is created (`room()`, `:301`).
- New mode `{ kind: "whimsy" }` card, opened from the `S`ettings card's footer and from the `help`/menu list
  (`:716-725`) as "the wackiness dial". Rows: preset (`1`–`4` pick), then one row per dial; a key flips/cycles
  it; the title reads `WACKINESS · casual` or `WACKINESS · casual (custom)`; `0` = back to the preset
  (`setPreset(whim, whim.preset)`). Per-event toggles listed under "events". Keys must not collide with globals or
  the sandbox play keys — `keys.test.ts`/the "no card key collides" test from c006255 will say.
- Banter gate: in `chatter()` (`:451`) when `!resolved.banter`: skip `room().converse` for server lines and
  make `onTogether` (`:456`) a no-op. Pets' lines (`room().hear`) are gated by `pets` in Task 3.
- Moods feed: where the TUI already sees a red build (the Scharlach ledger ticks on one — grep
  `ledger` in `tui/main.ts`/`kit/scharlach.ts`), also `room().sourMood(agent)`. If the red-build hook is in
  `kit/` not `tui/`, add the call there. Read-only on history; writes nothing to the server.
- `e` key (`:1998`): when the event's toggle is off or frequency is irrelevant, status reads
  `"events are switched off (wackiness: …)"`.
- Souls & weirdness: `souls: false` → skip `room().pinboard`'s soul-project notes (find with
  `grep -n "soul" rooms/wide.ts kit/sim.ts tui/main.ts`); `weirdness: "curated"` → only the curated `PARTS`
  ids in the hall's candidate pool, `"procedural"` adds generated dials, `"invented"` allows invented parts
  (**unverified**, see Decision 7 — if the hall has one pool, gate at `kit/hall.ts`'s candidate generator and
  say so).

Test first (`whimsy-card.test.ts`, pure over a `whimsyRows(state)` function exported from `tui/whimsy-card.ts` so
it needs no terminal — follow how `confirm.test.ts` / `reader.test.ts` test rows): rows show the preset and
"(custom)" after one override; `0` clears it; a flipped event toggle appears as one row off, the rest on.
Then drive once with the `drive-office` skill (`office:sandbox`): open the card, pick `rimworld`, press `e`,
read the status line; pick `business`, press `e` → "switched off". Record the screen text in the PR.

Done: `cd office && bun test test/whimsy-card.test.ts test/keys.test.ts`. Commit: `office: the wackiness dial card, in office.json`.

## Task 6 — the one rule, as a test, and the gate

Files: `office/test/whimsy-work-untouched.test.ts` (new); `docs/plans/2026-10-08-office-as-a-toy-design.md` §7/§8.

- Test: reading `kit/whimsy.ts`, `kit/whimsy-file.ts` and the new Sim/event code as text, none imports from
  `../tui/data` or calls `send(`/`call(` — `grep`-style assertion; plus a behavioural one: run `rimworld` for
  200 000 seeded ticks with a `data.send` spy installed → zero calls. This is the "chaos lives in the room"
  check, executable.
- Docs: replace design §7's `whimsy off|some|lots` paragraph with the preset/dial model (a table of the four
  presets), and mark §8 step 6 built with the check string above. Only these two spots.
- Gate: `mise run check` green.

Done: `bun test test/whimsy-work-untouched.test.ts` then `mise run check` exit 0 (paste the tail). Commit:
`office: whimsy never touches the work — a test, and the design doc says so`.

## Out of scope (named, not dropped)

- The server's `banter` knob still spends model tokens when the office hides the lines; a real off-switch is the
  server's `operator_config` (separate ticket — file it with `list_tickets` first).
- Per-seat room reactions to chained events are step 7; the chain uses the existing `onEvent` hook only.
- `mode` (office|sandbox) switching at runtime: the card shows it, `--sandbox` stays the way in.
