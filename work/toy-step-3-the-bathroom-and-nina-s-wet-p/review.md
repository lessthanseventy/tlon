# Review — toy step 3: the bathroom and Nina's wet paws

*Reviewed by tzinacan: no free reviewer was at the builder's grade (greybeard), so this is a lower-grade review.*

**Verdict: approve.**

The one blocker from the previous round (lonnrot's request_changes) is fixed in bfd0ca9, and it has a test.

## Verified

- **Argos's trail route.** `kit/pets.ts` now routes to the bathroom door spot (`DOOR.y - 3`, aisle `DOOR.y + 5`), then steps to the first print and along the trail. That is how Nina went, so the route no longer crosses the right wall.
- **Regression test.** The new `pets.test.ts` case seeds a trail starting at `RIM_FLOOR` and walks his whole path pixel by pixel against `plan.blocks` with inclusive bounds. The inclusive bounds matter: the walls are 2 px wide and an interior-only check misses them.
- **Tests.** `bun test test/pets.test.ts test/bathroom.test.ts test/bathroom-trip.test.ts test/pastimes.test.ts` gives 66 pass, 0 fail.
- **Rest of the diff, read in full** (the sim, the tile, the wide room, the TUI key and the voices):
  - The drink errand ends with `c.errand = null` and sets the wet timer.
  - Prints lay only while `tick < c.wet`, in `STRIDE` steps, and `prune` runs each step.
  - `creep` is cleared when his path ends.
  - The `b` key and the `bathroom` pastime/kind are wired consistently across `Pastime`, `LOUNGE_KINDS`, `LOUNGING` and `MOODS`.
  - I saw nothing else blocking.

## Not verified

I did not run the full `mise run check` gate. The tmux/unix-socket tests (refresh, terminal) cannot run in my sandbox, and the previous review recorded the same limit. The gate or merge step has to cover those.

## Non-blocking

- The refresh.test hardening commits ride along on this bathroom branch. They would bisect better as their own PR; not worth blocking on.
