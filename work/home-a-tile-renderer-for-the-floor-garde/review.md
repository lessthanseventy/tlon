VERDICT: approve

Read from the diff (main...HEAD). I did not run the suites or the live drive; the gate (`mise run check` exit 0) and emma's 246-pass office run are the server's and the builder's evidence, not mine.

**Spec/plan fit.** The annex is the plan's slice: `paintAnnex` and `annexHeight` in `kit/homeart.ts`, `WideRoom.setHome` and `height`, and the TUI loading the home and reloading it on leaving build mode. An empty home gives `annexHeight` 0 and an early return in `paintAnnex`, so the frame is unchanged, as the plan says. The annex is painted after `nightfall`, so it is not dimmed at night.

**Correctness.** `Math.min(...tiles.map())` is only reached when `tiles.length > 0`: both callers guard it. `layoutScreen` calls `room()` after `wide` is set, so the geometry sees the right height. Rooms created later get the home through `room()`. Rooms that already exist get the new home when you leave build mode.

**Nits, none blocking.**
1. `office/rooms/wide.ts`: `setHome` and `height` were inserted between `/** the remote: the next channel */` and `channel()`. That doc comment now sits above `setHome`, so `channel()` has none. Move the remote comment back above `channel()`.
2. The TUI wiring in `main.ts` has no unit test and the live drive was not done (emma says so). It is unverified beyond typecheck and the suites.
3. `layoutScreen` has an inline IIFE, `(r0 => r0 instanceof WideRoom ? r0.height : WIDE_H)(room())`. A local `const` would read better.
4. Goldens re-hash at each floor-render landing (learning #675), so run `mise run office:golden` at the merge gate.