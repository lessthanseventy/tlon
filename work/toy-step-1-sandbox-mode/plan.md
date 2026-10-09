# Toy step 1 — sandbox mode: plan

Source: `docs/plans/2026-10-08-office-as-a-toy-design.md` §1, §8 step 1. Ticket #52.
Nothing sandbox-related is on main (checked: no `--sandbox`, no fake source in `tui/data.ts`).
All paths are under `office/`. Gate: `mise run office:check` (typecheck + `bun test` at 03:00 and 15:00).

## Decisions I'm making (say so if wrong)

1. **The seam is `call()` in `tui/data.ts`.** One `useFake(handler)` hook; when set, every `data.*`
   read/write goes to the handler instead of `fetch`. So no TUI code changes for reads, and writes
   (file a ticket, close a thread…) answer "it's a toy" instead of failing weirdly.
2. **The world is a constant** (`tui/sandbox.ts`): the §2 roster names + `scharlach`, four pretend
   threads, a "Toy" workspace, weather. `looks.json` overrides already apply by name via the existing
   `followLooks`, so the bench *is* the user's bench wherever names match. No file read, no server.
3. **Play keys shadow the browse keys in sandbox only** (`c t f w n p` are crew/threads/archive/tray/
   new-thread/pet today; `d e` free). They go *before* a card's own actions. `tab` still opens the crew.
   Normal mode is byte-for-byte unchanged.
4. **Doorbell, event, fire drill have no scenes yet** (steps 3–5). Step 1 ships the keys and a
   placeholder `Sim.play(kind)` (everyone gets a `!`, one person says a line). Steps 3–5 replace its body;
   the key wiring stays. Same for `Sim.pat`.
5. **`n` night** = a clock override (`Sim.setClock` + `render(..., now)`), toggling 23:00 ⇄ real time.

## Task 1 — the made-up world (pure, no I/O)

Files: `tui/sandbox.ts` (new), `test/sandbox.test.ts` (new).

Test first:
```ts
import { expect, test } from "bun:test"
import { toy } from "../tui/sandbox"

test("the world is a full, ok snapshot with no server", () => {
  const t = toy(), a = t.snapshot()
  expect(a.ok).toBe(true)
  expect(a.bench.map((c) => c.name)).toContain("scharlach")
  expect(a.threads.length).toBeGreaterThanOrEqual(3)
  expect(a.roster.every((s) => a.bench.some((c) => c.name === s.agent))).toBe(true)
  expect(a.weather).not.toBeNull()
})
test("w steps the weather round the ring", () => {
  const t = toy(), seen = new Set([t.snapshot().weather!.kind])
  for (let i = 0; i < 7; i++) { t.nextWeather(); seen.add(t.snapshot().weather!.kind) }
  expect(seen.size).toBe(7)
})
test("a call-over is a fresh consult visit from one coworker to another", () => {
  const t = toy()
  t.callOver("yu"); const v = t.snapshot().visits
  expect(v).toHaveLength(1)
  expect(v[0]!.to).toBe("yu"); expect(v[0]!.from).not.toBe("yu")
  expect(Date.now() - Date.parse(v[0]!.at)).toBeLessThan(1000)
})
test("night toggles a clock override", () => {
  const t = toy()
  expect(t.now().getHours()).toBe(new Date().getHours())
  t.toggleNight(); expect(t.now().getHours()).toBe(23)
  t.toggleNight(); expect(t.now().getHours()).toBe(new Date().getHours())
})
```
Run `cd office && bun test test/sandbox.test.ts` → red (no module).

Code (`tui/sandbox.ts`) — the shapes are `Agents`/`Seat`/`Thread`/`Coworker` in `kit/types.ts`; if
tsc objects to a field, match the type, not this sketch:
```ts
// The sandbox: a made-up world for the TUI to run on with no server (`office --sandbox`) — the toy
// in docs/plans/2026-10-08-office-as-a-toy-design.md §1. Same sim, same rooms; only the snapshot's source differs.
import { EMPTY, type Agents, type Visit } from "../kit/types"

const NAMES = ["scharlach", "tertius", "hronir", "lonnrot", "yu", "beatriz", "nolan", "emma", "ireneo", "daneri", "sonny"]
const TITLES = ["the doorbell", "teach Nina to code", "a fire drill, but gentle", "the great sticky-note audit"]
const WEATHER = [
  { kind: "clear", desc: "Clear", temp_c: 21 }, { kind: "partly", desc: "Partly cloudy", temp_c: 18 },
  { kind: "cloudy", desc: "Overcast", temp_c: 14 }, { kind: "fog", desc: "Fog", temp_c: 9 },
  { kind: "rain", desc: "Rain", temp_c: 11 }, { kind: "snow", desc: "Snow", temp_c: -2 },
  { kind: "storm", desc: "Thunderstorm", temp_c: 16 },
] as const

export function toy() {
  let w = 0, night = false, visits: Visit[] = [], who = 0
  const threads = TITLES.map((title, i) => ({ id: 101 + i, title, stage: i % 2 ? "build" : "plan", awaiting: null, workspace_id: 1, lead: NAMES[1 + i]!, live: true, seat: "desk" as const }))
  const bench = NAMES.map((name, i) => ({ workspace_id: 1, seat_id: i + 1, agent_id: i + 1, name, archetype: name === "scharlach" ? "sheriff" : "builder", lead: i === 1, model: null, ask: null }))
  const roster = threads.map((t) => ({ agent: t.lead, thread_id: t.id, title: t.title, warm: true, thinking: t.id % 2 === 0, workspace_id: 1 }))
  return {
    snapshot(): Agents {
      return { ...EMPTY, ok: true, workspaces: [{ id: 1, name: "Toy" }], archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }, { name: "sheriff", meta: false, read_only: true, model: "" }], bench, threads, roster, weather: { ...WEATHER[w]! }, visits }
    },
    nextWeather() { w = (w + 1) % WEATHER.length },
    /** someone else walks over to `to` (the sim reads a visit younger than a minute) */
    callOver(to: string) {
      const from = NAMES.filter((n) => n !== to)[who++ % (NAMES.length - 1)]!
      visits = [{ from, to, workspace_id: 1, at: new Date().toISOString() }]
    },
    toggleNight() { night = !night },
    now(): Date { const d = new Date(); if (night) d.setHours(23, 0, 0, 0); return d },
  }
}
export type Toy = ReturnType<typeof toy>
```
Done: the 4 tests pass; `bun run typecheck` clean. Commit: `office: the sandbox's made-up world`.

## Task 2 — `data.ts` fake source

Files: `tui/data.ts` (edit `call`, +1 export), `test/data.test.ts` (append).

Test first (append to `test/data.test.ts`; it needs no server, so put it in its own `test()`):
```ts
test("a fake source answers every call; a write says it's a toy", async () => {
  const data = await import("../tui/data")
  const { toy } = await import("../tui/sandbox")
  data.useFake(toy())
  try {
    const all = await data.status()
    expect(all.ok).toBe(true); expect(all.bench.length).toBeGreaterThan(3)
    expect(await data.needs()).toEqual([])
    expect(await data.ticketFile(1, "x")).toContain("toy")
  } finally { data.useFake(null) }
})
```
Code: in `data.ts` add `import type { Toy } from "./sandbox"`, then
```ts
let fake: Toy | null = null
/** the sandbox's world instead of the server (`office --sandbox`) */
export const useFake = (t: Toy | null) => { fake = t }
```
and at the top of `call`:
```ts
if (fake) {
  if (method !== "GET") return { status: 409, json: { error: "it's a toy — nothing here to change" } }
  return path === "/office" ? { status: 200, json: fake.snapshot() } : { status: 404, json: null }
}
```
(`status()` reads `j.roster ?? []` etc., so the snapshot passes through; every other read already
tolerates a non-200 as empty/null.) Done: test green; existing data tests untouched and green.
Commit: `office: data.ts can read a made-up world`.

## Task 3 — `office --sandbox` / `mise run office:sandbox`

Files: `tui/main.ts` (startup), `tasks/office.toml` (new task), `../AGENTS.md`/`AGENTS.md` task manual line if `mise run check` names it.

In `main.ts` near the top-level state: 
```ts
const SANDBOX = process.argv.includes("--sandbox") || process.env.OFFICE_SANDBOX === "1"
const world = SANDBOX ? toy() : null
if (world) data.useFake(world)
```
(+ `import { toy } from "./sandbox"`). In `main()`, skip nothing else: `refresh()` now reads the toy.
`relaunch` already forwards `process.argv`, so `--sandbox` survives; but guard `updated()` — `officeRev` is
null in sandbox so `R` offers nothing.

`tasks/office.toml`:
```toml
["office:sandbox"]
description = "office: the TUI on a made-up world — no server, nothing staffed, everything pokeable (d e t f n w p c on the help line)"
dir = "office"
run = "bun tui/main.ts --sandbox"
```
Verify (the `drive-office` skill; private tmux, never the operator's terminal): with the server stopped or
`TLON_URL=http://127.0.0.1:1`, `mise run office:sandbox` shows the bench at desks and the whiteboard's four
threads, header not "channel down". Done = that screen + `mise run check` names the new task.
Commit: `office: office --sandbox runs on a made-up world`.

## Task 4 — the sim's two small hooks

Files: `kit/sim.ts`, `test/sim.test.ts` (append).

Test first, in `sim.test.ts` style (cast to reach `protected`; use an existing `WideRoom`/`Sim` fixture from `pastimes.test.ts`):
```ts
test("play rings every head with a !, and one person says a line", () => {
  const room = new WideRoom(560), a = viewOf(office(["hronir", "yu"]), 1)
  for (let i = 0; i < 50; i++) room.step(a)
  room.play("doorbell")
  const r = room as unknown as { actors: Map<string, { emote: string | null }>; talk: Map<string, { text: string | null }> }
  expect([...r.actors.values()].every((x) => x.emote === "!")).toBe(true)
  expect([...r.talk.values()].some((t) => t.text)).toBe(true)
})
test("pat gives that coworker a heart; false for a stranger", () => {
  const room = new WideRoom(560); room.step(viewOf(office(["yu"]), 1))
  expect(room.pat("yu")).toBe(true); expect(room.pat("nobody")).toBe(false)
})
test("setClock moves the hour the sim and the dark follow", () => {
  const room = new WideRoom(560); room.setClock(() => new Date(2026, 9, 8, 23))
  expect((room as unknown as { hour: () => number }).hour()).toBe(23)
})
```
Code in `Sim` (next to `disco`):
```ts
/** the toy's one-key happenings; steps 3–5 of the toy design give each a scene — this is the stand-in */
play(kind: "doorbell" | "event" | "drill") {
  const line = { doorbell: "Ding dong!", event: "Did anyone else hear that?", drill: "Fire drill! Everybody out!" }[kind]
  for (const x of this.actors.values()) { x.emote = "!"; x.emoteUntil = this.tick + 60 }
  const first = this.actors.keys().next().value
  if (first) this.say(first, line)
  this.changed = true
}
/** a pat for whoever (their name); false when they aren't in the room */
pat(name: string): boolean {
  const x = this.actors.get(name)
  if (!x) return false
  x.emote = "♥"; x.emoteUntil = this.tick + 60; this.changed = true
  return true
}
/** the clock the room runs on (the sandbox's `n`) */
setClock(now: () => Date) { this.hour = () => now().getHours() }
```
Done: 3 tests green at both `OFFICE_TEST_HOUR=3` and `15`. Commit: `office: sim — play, pat and a settable clock`.

## Task 5 — the play keys and the help line

Files: `tui/main.ts`, `test/sandbox.test.ts` (append a pure test of the key table).

Put the key table in `tui/sandbox.ts` so it is testable without a terminal:
```ts
export const PLAY: { key: string; label: string }[] = [
  { key: "d", label: "doorbell" }, { key: "e", label: "event" }, { key: "t", label: "treat" }, { key: "f", label: "fire drill" },
  { key: "n", label: "night" }, { key: "w", label: "weather" }, { key: "p", label: "pet" }, { key: "c", label: "call over" },
]
```
Test: `expect(PLAY.map((p) => p.key).join("")).toBe("detfnwpc")` and every `PLAY` key appears in `main.ts`'s `play()` switch (read the file text: `expect(src).toContain(`case "${k}"`)` for each — cheap guard against the help line drifting from the keys).

In `main.ts`:
```ts
/** sandbox only: one key, one thing to do with the toy; true when the key was one of them */
function play(k: string): boolean {
  if (!world) return false
  const r = room(), under = mode.kind === "person" ? mode.name : null
  switch (k) {
    case "d": r.play("doorbell"); status = "ding dong"; break
    case "e": r.play("event"); status = "something's up"; break
    case "f": r.play("drill"); status = "fire drill!"; break
    case "t": r.catDo("come"); if (r instanceof WideRoom) r.dogDo("office"); status = "treat! they come running"; break
    case "n": world.toggleNight(); r.setClock(world.now); status = world.now().getHours() === 23 ? "night falls" : "morning"; break
    case "w": world.nextWeather(); status = `weather: ${world.snapshot().weather!.desc.toLowerCase()}`; void refresh(); break
    case "p": if (mode.kind === "pet" && mode.who === "dog" && r instanceof WideRoom) r.patDog(); else if (under) r.pat(under); else r.pet(); status = "pat pat"; break
    case "c": world.callOver(under ?? world.snapshot().bench[1]!.name); status = `calling someone over to ${under ?? "the desk"}`; void refresh(); break
    default: return false
  }
  changed(); draw(); return true
}
```
(`mode.who` / `mode.name` per the existing `mode` union; `pat`/`play`/`setClock` live on `Sim`, so
they are on both room kinds. If `RailRoom` lacks `dogDo`, the `instanceof` guard is what the file already does.)
Hook it first in `onKey`, after the picker/input/confirm/editor/reader guards and **before** `const own = …`:
`if (play(k)) return`. Pass the clock to the render: line ~1290 `room0.render(a, {…}, measure, world?.now())`.
Help line: `const globals = [...(world ? PLAY : []), ...GLOBALS].filter(...)` at the `claimed` filter (~1356) — but the
sandbox keys must not be filtered out by a card's claimed keys, so build it as `[...(world ? PLAY : []), ...GLOBALS.filter(not claimed)]`.
Done (the check, with `drive-office`): each key in a sandbox session — `d` shows `!` over heads and a line, `e`/`f` likewise
with their line, `t` Nina and Argos head to the desk, `n` the windows go dark and lamps light, `w` steps the window sky,
`p` a ♥ on the card's person (Nina by default), `c` someone walks to the card's person; the help line lists all eight;
a normal (non-sandbox) launch shows none of it and `c t f w n p` do what they did. Commit: `office: sandbox play keys`.

## Task 6 — docs, then the gate

Files: `office/AGENTS.md` (one bullet in the `tui/` entry: `--sandbox`, `tui/sandbox.ts`, the seam in `data.ts`, the shadowed keys),
`docs/plans/2026-10-08-office-as-a-toy-design.md` (step 1 → "built; `Sim.play` is the stand-in steps 3–5 replace").
Also amend the AGENTS.md law line "The TUI talks to the server only over the operator API" with "(or, in `--sandbox`, to `tui/sandbox.ts`)".
Done: `mise run office:check` green; `mise run check` green. Commit: `office: document the sandbox`.

## Out of scope (named, not forgotten)
Real scenes for doorbell/events/fire drill (steps 3–5), voices (2), `mode`/`whimsy` in `office.json` (6, §7 — the flag is the only switch for now), a "this is a toy" banner.
