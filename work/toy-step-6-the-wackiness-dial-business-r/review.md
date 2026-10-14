## verdict: approve

Toy step 6 lands the wackiness dial (preset + per-dial overrides + toggles) with the spec's four checks
made executable and green. The branch's own diff (`22a41af..HEAD`) is clean office work; the server/CI/test
"deletions" in a straight `main..HEAD` are main-divergence noise — the branch is 7 commits behind main
(cut from `22a41af`), and the merge gate rebases.

### Spec checks — all tested, all green (office:check 645 tests, `mise run check` exit 0 at verify)
- **business plays no event and no banter** — `whimsy-sim` "business plays no event and rings no bell"; banter
  gate in `chatter()` (skips `room().converse` and no-ops `onTogether`).
- **rimworld chains events** — `whimsy-chain` "an event can start the next the moment it ends"; `CHAINS` table,
  depth ≤3, draws only when `chain` is on; `chain: false` never chains (asserted).
- **a dial overridden under a preset holds** — `whimsy` "a dial overridden under a preset holds"; state is
  `{mode, preset, overrides}`, "custom" is derived, choosing a preset clears overrides.
- **the work is never touched** — `whimsy-work-untouched`: an import-no-data grep over the kit/room/card files
  AND a 22k-tick rimworld run that leaves the agents snapshot byte-for-byte unchanged. This is the load-bearing
  one and it is real.

### Correctness spot-checks
- `propsAt(k,t,g,1)` deep-equals the old `propsAt(k,t,g)` by construction (severity copies run 40 ticks behind;
  the `i === 0` filter is a no-op at severity 1) — asserted in `whimsy-chain`.
- `pickEvent` with a single enabled kind repeats it (`fresh` empty → falls back to `from`) — asserted.
- The scheduler draws no `Math.random` before the first event (first `nextEvent = tick + gap`, no random), so
  seeded golden frames are untouched — consistent with `wide.test.ts` green.
- `stepDoor` gates rings on `doorbell !== "off"` each tick, so turning the bell off mid-run stops rings without
  needing `nextRing = Infinity`. Equivalent to the plan's intent; the "rimworld + doorbell off" test confirms.
- Moods feed reads the Scharlach ledger (already-maintained triage) and writes only the room-local `sour` map —
  no server write; `sourMood` under `moods: false` is a no-op (asserted).

### Honest, already-ticketed deferrals (named in pr.md, not blockers)
- `souls` / `weirdness` stored but unwired — #323, #97/#98; the card says "not wired yet".
- banter gate is presentation-only for fetched `data.banter` lines (the `onTogether` no-op does save `data.talk`
  calls, but `data.banter` / `data.pets` are still fetched) — #363.
- not driven live in the wide room (kitty graphics) — same gap as #161/#162.

### One landing heads-up (non-blocking)
Main's 46cdec6 / a0900a9 / 443a4a7 edit `tui/main.ts` in the same regions the whimsy wiring touches (the `Mode`
union, `room()`, `detail()`). The merge-gate rebase will conflict there; resolve by hand. No content issue — the
whimsy additions sit in new branches of those switches.

The deferrals are already ticketed, so no new follow-ups. Approving.