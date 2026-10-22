# Review — toy-gary-the-dumpster-gremlin-69

**Verdict: approve**

A new `gary` toy event (office-only, no server change). No correctness bugs found; the gate is green (tsc clean, 863 pass / 0 fail).

## What changed

- `kit/events.ts`: a `"gary"` event (540 ticks, bounded), added to `EVENT_KINDS` and `CHAINS` (`gary: []` — no chain). `garyRoll` splits a roll into thirds (`sandwich`/`sock`/`slap`); the roll is drawn once in `Sim.event` at start, so a seeded run replays it. `garyScene` is pure: dumpster at `doorX−24`/`hallY`, lid shut → out with bone + mutter → outcome at `GARY_ACT=300` → back in by 500. `peek` shows lid+eyes only. `propsAt` forces severity 1 for gary (no multi-Gary). `garyLeads` puts him 16px ahead of the zoo's lead penguin (rimworld only, not via CHAINS). New `PropKind`s (dumpster, gary, bone, sandwich, sock, stars, shout, mutter, cackle) and a `text` field on `Prop` for the shouts.
- `kit/sim.ts`: the SLAP lands at `t===GARY_ACT` on the nearest non-leaving actor (ties by agent name), fires `onSlap` exactly once, and `spin()` cycles the victim's face + stars for `GARY_SPIN=60`. `running` gains an optional `gary` field (outcome/peek/victim), set only for `k==="gary"`.
- `kit/whimsy.ts`: a `gary: peek|visit|lead` dial per preset (business: peek but events.gary off; casual: peek; party: visit; rimworld: lead), parsed and resolved.
- `kit/scharlach.ts` / `tui/main.ts`: `tickSlap` ticks one demerit against Scharlach; `onSlap` wired to it in the `room()` factory.
- `kit/seat-voices.ts` / `kit/voices.ts` / `kit/pets.ts`: a `gary` line for every seat, Nina, and Argos.
- `kit/zoo.ts`: sprites for the new props + a `SHOUTS` table for the overhead text.

## Correctness checks

- `event("gary")` guards on `dials.events[kind]`, so business (events.gary off) stays out even when asked — confirmed by the test.
- `react(k)` at start reads the server pool keyed `SERVER_EVENT[gary]="gary"`; the server has no such key, so it no-ops. Seat-voice reactions come through the `react:true` beat at t=60. No double reaction.
- `slap` measures distance from the dumpster prop at `propsAt("gary", 0, g)`; the victim is set before `spin()` runs in the same `step` tick (stepEvent → movement → spin). Stars draw over `[GARY_ACT, GARY_ACT+GARY_SPIN)`.
- `garyLeads` returns `[]` for non-zoo kinds, so no double Gary during a gary event in rimworld; during a gary event there, `peek` is false (lead ≠ peek) so the full visit plays.
- `golden.json` untouched; the golden test still passes, so Gary doesn't leak into the deterministic frames.
- `heightOf` exists in `sprites.ts`; `ledger` is a module `let`, so the `onSlap` closure reassigns it cleanly (same pattern as `tickFromTriage`).

## Tests

`test/gary.test.ts` (183 lines): the roll thirds; bounded event; dumpster position; peek = lid+eyes only; visit beats; each outcome's props; severity-forced to 1; `garyLeads` ahead of the penguin; dial per preset + override parse; `tickSlap` demerit; in-room business exclusion, casual peek, party sandwich/sock/slap (nearest victim, spin ≥3 faces, ledger), same-seed replay, rimworld zoo lead vs casual no-lead. Existing `events.test.ts` and `whimsy-sim.test.ts` updated for the sixth kind.

## Non-blocking follow-up

The pr.md notes the change was not eyeballed in the running TUI. The office's own law says a frame change is "seen, not assumed." Golden + WCAG tests pass, but the new pixel sprites deserve an eyeball before they reach the operator's screen.