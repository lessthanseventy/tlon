# Toy step 5: the events — spec

Design: `docs/plans/2026-10-08-office-as-a-toy-design.md` §3, §8 step 5. Ticket #56 (office, toy).
Check (design): **each plays and tidies itself; none touches a thread or a turn.**

## What exists, what this adds

Main already has the **fire drill** (§2, Scharlach's): `Sim.play("drill")` sets `drillUntil`/`alarmSince`;
`PANIC` ticks of running about and screaming, then a muster at `plan.muster` (`DRILL` = 600 ticks); the
rack burns (`closet()` in `rooms/wide.ts`), Nina zooms, Argos barks at the smoke. A down channel is never
this (`Sim.held`).

`Sim.play("event")` is a **stand-in**: everyone gets `!` and one says "Did anyone else hear that?".
Steps 3 and 4 replaced the other stand-in (`doorbell`) with `ring()`; step 5 replaces this one.

| Event | Today | Step 5 |
|---|---|---|
| fire drill | built (`f`) | **reused unchanged**; becomes one of the five the event layer knows about (so step 6's scheduler can pick it), gains Scharlach calling it |
| zoo's open day | — | new scene |
| meteor | — | new scene |
| power cut | — | new scene |
| duck | — | new scene |

So step 5 adds: **the scripted, self-tidying, thread-free scene framework** (`kit/events.ts`) plus the
four scenes on it. It does not rework the drill's choreography.

## Decisions (each cheap to flip — say if you disagree)

1. **The framework is a table of scripts, not a state machine per event.** `EVENTS: Record<EventKind,
   Script>`; a `Script` is `{ ticks, beats: {at, do}[] }` — each beat a pure function of the scene state
   (a line to say, an emote, a prop to place, a figure's path). One `Sim.event: {kind, since} | null`;
   at `since + ticks` it is set to `null` and every prop is dropped. One event at a time; a second request
   while one runs is ignored (returns false), as `ring()` does for a full queue.
2. **Events live only in the sim.** No import of `data`, `talk`, `reader` or any `/api` module in
   `kit/events.ts`; nothing about an event is written to the state dir, the banter log or the snapshot.
   A test fixes this: with threads, a thinking lead and a warm roster in the snapshot, a full event of
   each kind leaves `Agents` deep-equal and `Sim` actors' `thinking`/`warm` untouched.
3. **A coworker mid-turn stays at their desk.** The server's `thinking` seats keep working in the
   picture: they glance up (`!`) and may say a line, but are never pulled off the desk. Idle and lounging
   coworkers do the running, chasing and rushing to the window. (The existing drill pulls everyone; left
   as is — flag if you want it to match.)
4. **Time**: each event runs 600–1200 ticks (1–2 min at 100 ms). Length is in the script, not a global.
5. **Triggers in this step: keys and the API only.** `Sim.event(kind?)` starts one (no kind → a draw that
   is not the last event). Sandbox `e` calls it; `f` stays the drill. **No scheduler, no `whimsy` read,
   no per-event toggle** — those are step 6 (#57). Hook left for it: `Sim.event` is the only entry, and
   `EVENTS` is the list a toggle filters.
6. **Hook for step 7 (#58, the cast reacts)**: `Sim.onEvent: ((kind, beat) => void) | null`, fired at
   start and at each beat, default null — the same shape as `onTogether`. Step 5's own lines are
   scripted for named roles only (Scharlach; "the first idle coworker" blames the deploy). Per-seat
   voices are step 7.
7. **Determinism**: no `Math.random()` per tick while no event runs, so golden frames and the bathroom
   trip's seed streams don't shift; a draw happens only when an event starts and at its beats. Tests use
   `seeded()` from `test/golden.ts`.
8. **The crater is part of the meteor scene** and goes with it (the design's "gone by morning" is the
   joke; it is not persisted across ticks or sessions).
9. **No new server work.** Entirely `office/`; no snapshot field, no endpoint.

## The scenes

Geometry comes from the `Plan` (`plan.door`, `plan.exit`, `plan.lounge`, window spots from the wide
room); the rail room has none of it, so there `Sim.event` starts nothing and returns false (as `ring()`).

- **Zoo's open day** (~1200). A ZOO van pulls up outside the door; the door opens. Monkey enters, swings
  along the light fittings (drawn on the ceiling row, hopping x), penguin waddles the hall and lounge, goat
  walks to the corkboard and eats a note (the note is hidden while it chews, back at the end — the cork is
  not changed). Scharlach (if seated and idle) chases with a net, "Order! ORDER!"; Nina on the fridge,
  Argos delighted (existing pet modes). End: animals walk out of the door, van leaves.
- **Meteor** (~700). A streak across the window pane, a puff at the street, a small crater drawn there;
  the lamps flicker (alternating `lampsLit` ± for a few beats); idle coworkers go to the window spots;
  one says "…was that the deploy?". The crater is removed at the end.
- **Power cut** (~700). `blackout` flag: lamps out (the same overlay `dark` uses), screens keep their
  glow, a candle is placed at one idle coworker; the lamps return and everyone gets `♪` (applause).
- **Duck** (~500). One duck walks in at the door, crosses the hall, looks around (turns), leaves. Argos
  watches. Nothing else.
- **Fire drill**: `Sim.event("drill")` ≡ `play("drill")`, plus Scharlach says "Fire drill! Everyone out!"
  first (his §2 call). Nothing in the choreography changes.

## Out of scope, named

- Scheduler / frequency / per-event toggles (step 6), per-seat reactions (step 7), the wackiness dial.
- Sandbox `d`/`f` and the doorbell: untouched.
- Sprites are small blit grids in `kit/zoo.ts` like `drawVisitor`; art polish is not this step.

## Tests

`office/test/events.test.ts` (new; `mise run office:test`): each kind starts, runs to its length and
leaves the sim's props empty; a second start mid-event is refused; the snapshot is deep-equal before and
after with threads/thinking seats present; a thinking seat never leaves its desk; `seeded` run is the
same twice; the rail room starts none. `mise run office:golden` unchanged (no per-tick draw).
Verify: `mise run check`.
