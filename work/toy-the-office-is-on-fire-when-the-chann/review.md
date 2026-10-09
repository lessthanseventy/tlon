NOTE: no free reviewer was at the builder's grade (greybeard); this review is by tzinacan at a lower grade — weigh accordingly.

# Verdict: approve

Read the full diff (main...HEAD, office/ only). I did not re-run the suite; the thread's recorded `mise run check` and verify evidence are green.

What I checked by reading:
- Fire state machine (`sim.ts`): FIRE_GRACE debounces restart blips; `seeded` guard keeps a never-up room from burning; recovery clears and sets `changed`. Tests cover all three.
- Drill: everyone goes to a distinct muster spot with a mug; return after recovery is tested. Argos holds at the muster and doesn't go to bed in a fire (seed-pinned test).
- golden.json hashes change because the closet is now always drawn — expected, all five widths moved together.
- Docs: office/AGENTS.md updated in the same change.

Non-blocking notes (no change requested):
1. `rooms/rail.ts` also extends `Sim`, so a held outage there sets `fire` and the crew all stack on `plan.exit` (no `muster`), with no closet to burn. Harmless but odd; if the rail room should stay calm, gate `fire` on `plan.muster`.
2. Muster has 16 spots; a crew over 16 wraps and shares a spot. The distinctness test only covers the fixture crew.
3. `[...this.actors.keys()].indexOf(k)` runs per actor per tick while burning — O(n²), fine at office scale.
