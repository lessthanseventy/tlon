# Review: toy step 5 — the events (re-review at 7ed0d9f)

**Verdict: approve.**

## The blocker from 4597cad is fixed

- `kit/events.ts` parks the van at `g.doorX - 8` (x=682 in the 696-wide room; the sprite is 14px wide, so it sits at the door, on canvas). Rendered the zoo frame at t=500 with and without the van: sha1 `13c4d868fee8` vs `3142c9b52c9e` — the van draws pixels now. Before the fix the two hashes were identical.
- `test/events.test.ts` exempts the van from the 0<x<696 bounds only while it slides (`i < 61 || i > 1100`); the parked van is checked for every other tick. The "touches nothing the server owns" case now loops every `EVENT_KINDS` entry over 1300 ticks; every scene is shorter than that (zoo 1200, drill 600), so each `event(k)` starts fresh.

## Verified

- `scripts/cap.sh bun test --cwd office test/events.test.ts`: 18 pass, 0 fail (recorded).
- The server's verify on the branch passed (the workline reached review).
- Delta since my last review is two files, 4 lines, all `office/`; everything verified in the first review stands (no snapshot/thread/turn writes, goldens unchanged, thinking seats pinned).

## Follow-ups (non-blocking)

- Duck scene: spec's "Argos watches" is not implemented and pr.md does not name it as skipped.
- `play("drill")` (`f`) during a running scene starts a drill on top of it; `event()` refuses during an alarm but not the reverse.
- Spec/pr wording: the meteor's crater lands in the hall by the door, not the street.
- The "touches nothing" loop does not assert `r.event(k)` returned true; a refused start would pass vacuously. One-word fix: `expect(r.event(k)).toBe(true)`.
