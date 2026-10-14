# office: toy step 7 — the cast reacts to events, in voice

Closes #58 (office-as-a-toy design §8 step 7). Presentation only: nothing here touches a thread, ticket,
turn or the server.

- `kit/seat-voices.ts`: `SEAT_REACT` — two lines per seat per event kind, each in the §2 voice — and `reactLine`.
- `kit/events.ts` / `kit/sim.ts`: a `react` beat asks each idle seat (the sheriff first) for its own line, 20 ticks
  apart, through a `Sim.reactLine` hook (null by default, so seeded traces don't move). A thinking seat is never asked.
- `tui/main.ts`: wires the hook to `reactLine`, sharing the banter's recent-lines memory.
- Nina (zoo, meteor, power, duck) and Argos (all five; overjoyed at the zoo) get event lines. The drill keeps
  Nina's zoomies as her reaction.
- Not built: Nina on the fridge for the zoo (plan task 5, optional).

Checked: `cd office && bun test` (events, seat-voices, pets tests added; determinism and "an event touches nothing
the server owns" still green), `bunx tsc --noEmit` clean.
