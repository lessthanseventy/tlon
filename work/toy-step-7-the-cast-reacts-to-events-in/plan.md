# Toy step 7 — the cast reacts to events, in voice (ticket #58)

Design: docs/plans/2026-10-08-office-as-a-toy-design.md §2, §3, §8 step 7.
Check: **every seat reacts to each event in its own way.** Presentation only — nothing here touches a thread,
ticket, turn or the server (the existing "an event touches nothing the server owns" test must stay green).
All work is in `office/`. Gate: `cd office && bun test` per task; `mise run check` before landing.

## What is already on main (do not rebuild)
- `kit/events.ts`: the five scripts and their props. Beats are *generic*: one line for "the sheriff" (Scharlach
  only) or "the first idle coworker", plus `emote` glyphs. No seat has its own reaction.
- `kit/sim.ts` `event()/beats()`: runs beats, calls `onEvent(kind, beat|null)`; the doc comment says "step 7's
  cast reacts here". `this.running.idle` is the sorted crew list (not thinking, not leaving).
- `kit/seat-voices.ts`: `SEAT_VOICE[seat].banter` + `seatLine()` for room chatter. No event lines.
- `kit/voices.ts` (Nina, `NINA`, `bucketFor`) / `kit/pets.ts` (`ARGOS`, `argos()`): occasions, none for events.
  Argos only has `smoke` for the drill.
- Gap = (a) per-seat event lines, (b) Nina and Argos event lines, (c) Nina on the fridge for the zoo (cuttable).

## Task 1 — per-seat reaction lines (data + test)
Files: `office/kit/seat-voices.ts`, `office/test/seat-voices.test.ts`.
1. Test first (add to seat-voices.test.ts):
   ```ts
   import { EVENT_KINDS } from "../kit/events"
   import { SEAT_REACT, reactLine } from "../kit/seat-voices"
   describe("event reactions", () => {
     test("every seat has at least two lines for every event", () => {
       for (const s of SEATS) for (const k of EVENT_KINDS) expect(SEAT_REACT[s]?.[k]?.length ?? 0).toBeGreaterThanOrEqual(2)
     })
     test("seats do not share a line", () => {
       const all = SEATS.flatMap((s) => EVENT_KINDS.flatMap((k) => SEAT_REACT[s]![k]!))
       expect(new Set(all).size).toBe(all.length)
     })
     test("reactLine skips what was said lately and falls back for an unknown seat", () => {
       const l = SEAT_REACT.yu!.duck!
       expect(reactLine("yu", "duck", [l[0]!])).toBe(l[1])
       expect(typeof reactLine("w9", "duck", [])).toBe("string")
     })
   })
   ```
   Red: `SEAT_REACT` not exported.
2. Implement in seat-voices.ts: `export const SEAT_REACT: Record<string, Partial<Record<EventKind, readonly string[]>>>`
   with 2 lines per seat per kind (11 seats × 5 kinds × 2 = 110 lines), each in the §2 table voice
   (tertius dry, yu anxious, nolan theatrical, daneri grandiose, sonny sunny, ireneo "I remember…", …;
   scharlach crisp/formal: drill "Muster point B. I have a clipboard.", zoo "This is a Class 3 incursion."…).
   `import type { EventKind } from "./events"`. Add
   `reactLine(name, kind, recent) = pickFresh(SEAT_REACT[name]?.[kind] ?? GENERIC_REACT[kind], recent)` using
   `pickFresh` from `./voices`; `GENERIC_REACT` = one-liner per kind for unnamed seats (w0, w1…).
Done: `cd office && bun test test/seat-voices.test.ts` green. Commit: `office: each seat's lines for each event, in voice`.

## Task 2 — the sim has seats react (staggered, one line each)
Files: `office/kit/events.ts`, `office/kit/sim.ts`, `office/test/events.test.ts`.
1. Test first (events.test.ts, in `describe("the cast")`):
   ```ts
   test("each idle coworker reacts once per event, in their own line, staggered", () => seeded(3, () => {
     const r = new WideRoom(696), a = view(["w0", "w1", "w2"]), said: Record<string, string[]> = {}
     r.reactLine = (who, kind) => `${who} on ${kind}`
     run(r, a, 300); r.event("duck")
     for (let i = 0; i < EVENTS.duck.ticks; i++) { r.step(a); for (const [n, t] of (r as any).talk) if (t.text?.endsWith(" on duck") && !(said[n] ??= []).includes(t.text)) said[n]!.push(t.text) }
     for (const n of ["w0", "w1", "w2"]) expect(said[n]).toEqual([`${n} on duck`])
   }))
   test("a seat that is thinking stays silent in an event", () => seeded(3, () => { /* w2 thinking per `view`; reactLine never called for it */ }))
   ```
   (Copy `view`'s thinking convention from the existing "a thinking seat never leaves its desk" test; assert the
   hook is never called with that seat.) Also update the existing `onEvent` test only if its expectation moves.
2. `events.ts`: `Beat` gains `react?: true`; add one `{ at: <t>, who: "idle", react: true }` per script —
   drill 60, zoo 120, meteor 100, power 120, duck 60 (before the generic lines, which stay).
3. `sim.ts`: `reactLine: ((who: string, kind: EventKind) => string | null) | null = null`. In `beats(t)`:
   for a `react` beat, for each `(n, i)` of `r.idle` when `t === b.at + 20 * i`: skip if `this.talk.get(n)?.text`
   is already live; else `const l = this.reactLine?.(n, r.kind); if (l) this.say(n, l)`. Do **not** call
   `onEvent` for react beats (keeps the existing `["duck:start","duck:200"]` test valid). The match must be on
   `t === b.at + 20 * i`, not `b.at === t`, so the loop shape changes for react beats only.
Done: `bun test test/events.test.ts` green incl. "an event touches nothing the server owns" and determinism
(the hook adds no `Math.random` — `reactLine` owns its randomness, null in tests).
Commit: `office: the room asks each seat for its line when an event beats`.

## Task 3 — wire it in the TUI and sandbox
Files: `office/tui/main.ts` (next to `room().onTogether`, ~L455), `office/test/` (extend `sandbox` test if one
exists, else `events.test.ts`).
1. Test first: a sandbox-driven test (see how existing tests drive `tui/sandbox.ts`) that after
   `room.event("zoo")` more than one distinct seat has spoken and each line is in `SEAT_REACT[seat].zoo`.
2. Implement: `room().reactLine = (who, kind) => { const recent = recentBanter.get(who) ?? []; const l = reactLine(who, kind, recent); recentBanter.set(who, [l, ...recent].slice(0, 8)); return l }`
   — reuses the existing `recentBanter` map. `import { reactLine } from "../kit/seat-voices"`.
Done: `bun test` green; `cd office && bun run tui/main.ts --sandbox` (see `mise tasks` → `office:sandbox`), press `e`
until a zoo plays: balloons differ per seat. Commit: `office: wire seat reactions into the room`.

## Task 4 — Nina and Argos react
Files: `office/kit/voices.ts`, `office/kit/pets.ts`, `office/kit/sim.ts`, `office/rooms/wide.ts`, tests in
`office/test/pets.test.ts`.
1. Test first (pets.test.ts): after `r.event(kind)` for each kind in a WideRoom, within 300 ticks Nina has said a
   line from `NINA["event_"+kind]` (or `SWEET`) and Argos one from `ARGOS["event_"+kind]`; zoo for Argos is
   the "overjoyed" pool. Use the file's existing helpers for reading `catSaid`/`dogSaid`.
2. Add occasions `event_drill|zoo|meteor|power|duck` to `NINA` (diva: "A goat? On MY corkboard?") and `ARGOS`
   (zoo: overjoyed, "ANIMALS! FRIENDS! ALL OF THEM!"; power: "Dark! Was that me?"; duck: "A DUCK. I love him."),
   2–3 lines each; `bucketFor` already falls back to the sassy bucket when no sweet exists.
3. `Sim.event()` after `this.onEvent?.(k, null)` calls `protected reactPets(k)`: base says Nina's line via
   `this.catSay(this.line("Nina", "event_"+k, NINA["event_"+k]), 90, 20)` (signature as used at sim.ts:342);
   `WideRoom` overrides to call super then `this.dogSay(this.argos("event_"+k))`. Argos' typing: widen
   `keyof typeof ARGOS` already covers new keys.
Done: `bun test test/pets.test.ts test/events.test.ts` green. Commit: `office: Nina and Argos react to events`.

## Task 5 — Nina watches the zoo from the fridge (cut if it fights the sim)
Files: `office/rooms/wide.ts`, `office/kit/tiles/kitchen.ts` (read only for the fridge x/y: `px(w-13,140,12,15…)`),
`office/test/events.test.ts`.
1. Test first: during `zoo`, between ticks 250–900, the cat's position is on the fridge top (assert x/y against a
   `fridgeTop()` the room exposes); after the event she is back to a normal mode within 200 ticks; seeded run is
   deterministic; "an event touches nothing the server owns" still green.
2. Implement an event goal for the cat in `WideRoom` (mirrors `Sim.eventGoal` for actors): route via the plan to
   the fridge's top spot, `mode = "sit"` with `until` = event end. If the planner has no route up (no
   climbable), instead pose her at the counter beside the fridge and say so in the commit — do not add new
   routing machinery for a joke.
Done: tests green; sandbox `e` until zoo shows Nina elevated. Commit: `office: Nina watches the zoo from the fridge`.

## Out of scope
Server/Elixir, persona generators (step 8 is built), settings-panel toggles (step 6), model-written reactions
(canned lines only, like `--sandbox` always), the bathroom/door/visitors.

## Order and risk
1 → 2 → 3 are the check; 4 completes the pets; 5 is optional. Risk: the stagger shifts the seeded traces in
`events.test.ts`'s determinism test only if `reactLine` is non-null in it (it isn't). The generic beats stay, so
a reaction may follow "Who let them in?" in the same balloon slot — `say` replaces, which is acceptable; the
react beat is scheduled after them for that reason.
