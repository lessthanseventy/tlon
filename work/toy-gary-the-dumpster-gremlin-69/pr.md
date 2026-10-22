Gary the Dumpster Gremlin: a new `gary` toy event (office only, no server change).

Closes #69.

What changed
- `kit/events.ts`: a `"gary"` event. The dumpster sits just outside the door (from `Geo.doorX`/`hallY`); Gary climbs out with a fish bone, mutters "I WILL END YOU, and then I will eat your yogurt", then the visit's roll comes up: steals a sandwich, leaves one sock, or SLAPs. `garyRoll` splits the roll into thirds; `garyLeads` puts him ahead of the penguin in the zoo.
- `kit/whimsy.ts`: a `gary` dial per preset. Business: never. Casual: peek only (lid and eyes). Party: full visit. Rimworld: visit, and he heads the zoo parade (not via `CHAINS`).
- `kit/sim.ts`: the roll is drawn once at the event's start. A SLAP hits the nearest coworker (ties by name), who spins with stars; `onSlap` fires.
- `kit/scharlach.ts` / `tui/main.ts`: `tickSlap` puts one demerit against Scharlach on the ledger after a SLAP.
- Sprites, and a line for every seat, Nina and Argos.

Not in this PR: the sandbox play key. `G` is `crew.g`, and every printable key is bound, so a play key means moving an existing binding; the operator chose to ship without it and follow up in its own ticket.

How it was checked
- `tsc --noEmit` in `office/`: clean.
- `bun test` in `office/`: 863 pass, 0 fail. New `test/gary.test.ts` pins all three outcomes, the nearest-victim SLAP and spin, the ledger demerit, peek/visit/lead per preset, none in business, and an identical replay under the same seed.
- Not checked by eye in the running TUI.
