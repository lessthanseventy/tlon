# Review: toy step 5 — the events

**Verdict: request_changes** (one blocker, cheap).

## Blocking

1. **The ZOO van never renders.** `kit/events.ts` parks the van at `g.doorX + 14`; in the wide room `doorX` = 690 (door at 678, exit at 693, width 696), so the van sits at x=704 for the whole scene and the canvas clips it. Checked by rendering the t=500 zoo frame with only the van vs. with no props: identical sha1. `test/events.test.ts` exempts the van from its 0<x<696 bounds check for every tick ("slides in from off-screen"), which is why 18/18 green did not catch it.
   Fix: park the van in frame — e.g. `const vanX = g.doorX - 8` (nose at the door; the room has 6px of street, so "outside" has to mean "at the door") — and narrow the test's exemption to the slide-in/out ticks (t<60 or t≥1100) so the parked van must be on canvas.
   While in that test: the "an event touches nothing the server owns" case runs only the meteor; the spec says each kind. Loop over EVENT_KINDS.

## Verified

- `scripts/cap.sh bun test --cwd office test/events.test.ts`: 18 pass, 0 fail. Server's `mise run check` on the branch: exit 0 (brief, 12:57Z).
- Diff is `office/` only; no server work, no snapshot field or endpoint. `kit/events.ts` imports only `Pt`; event lines go through `Sim.say` (the sim's talk map), nothing reaches the state dir or banter log.
- `Math.random()` only in `Sim.event()` with no kind; goldens unchanged (server check). `stepEvent` runs after `tick++` so no beat is skipped; the drill's `running` and `drillUntil` end on the same tick.
- Thinking seats: `event()` excludes them from `idle`, and the actor loop's `thinking → home` branch precedes `eventGoal`, so a seat that starts thinking mid-scene goes home. Test pins every non-drill kind.
- `e` falls back to the stand-in in the rail room (no door → `eventGeo()` null); `f` untouched. `office/AGENTS.md` updated in the same change.
- Crater is drawn at `doorX - 60` on the hall row, inside the office, not "the street" as the spec says. Accepted: this room has no street. Noted as a follow-up to say so.

## Follow-ups (non-blocking)

- Duck scene: spec's "Argos watches" is not implemented and pr.md does not name it as skipped.
- `play("drill")` (`f`) during a running scene starts a drill on top of it; `event()` refuses during an alarm but not the reverse. Decide whether `f` should refuse or end the scene.
- Spec/pr wording: the meteor's crater lands in the hall by the door, not the street.
