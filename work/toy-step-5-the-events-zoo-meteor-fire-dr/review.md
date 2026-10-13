# Review: toy step 5 — the events (re-review at 5c2931f)

**Verdict: approve.**

## The delta since 9f69625 (the QA fix)

One commit, 9 lines, three files, all `office/`:

- `kit/sim.ts`: `Sim.eventsHere()` returns whether `eventGeo()` is non-null. Public, read-only, no state touched.
- `tui/main.ts`: `e` now reads "events need the wide room (kitty graphics)" when the room cannot stage a scene, and keeps "something's up" for a refusal inside the wide room (a scene already running, an alarm, no actors). This is exactly QA's finding (nolan, message 7239): the rail view used to refuse silently.
- `test/events.test.ts`: pins `RailRoom.eventsHere() === false`, `WideRoom(696).eventsHere() === true`.

The rail room deliberately gets no event geometry: the scenes are staged on the wide room's hall and window (brief decision 1767). That is a design choice I agree with for this step; it stays out of the follow-ups.

## Verified

- `scripts/cap.sh bun test --cwd office test/events.test.ts test/rail.test.ts`: 25 pass, 0 fail (recorded).
- `bunx tsc --noEmit` in `office/`: clean (recorded).
- The server's verify (`mise run check`) passed on this branch at 14:36 and advanced it to review.
- Everything from the two earlier reviews stands: the van parks on canvas, the "touches nothing" case loops every event kind, no snapshot/thread/turn writes.

## Not verified

- The scenes' pixels in the wide room (ghostty, kitty graphics). Neither QA's tmux drive nor this review can see them; QA passed what it could reach. A PNG check in ghostty remains open for the operator or a later QA.

## Follow-ups (non-blocking, carried forward)

- Duck scene: spec's "Argos watches" is not implemented and pr.md does not name it as skipped.
- `play("drill")` (`f`) during a running scene starts a drill on top of it; `event()` refuses during an alarm but not the reverse.
- Spec/pr wording: the meteor's crater lands in the hall by the door, not the street.
- The "touches nothing" loop does not assert `r.event(k)` returned true; a refused start would pass vacuously. One-line fix: `expect(r.event(k)).toBe(true)`.
