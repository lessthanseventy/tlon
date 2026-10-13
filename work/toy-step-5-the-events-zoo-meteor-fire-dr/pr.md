# Toy step 5: the events — zoo, meteor, power cut, duck (+ the drill joins)

Closes ticket #56. Design `docs/plans/2026-10-08-office-as-a-toy-design.md` §3, §8 step 5.

- `office/kit/events.ts`: an `EVENTS` table of scripts (drill, zoo, meteor, power, duck) and the pure `propsAt` / `blackoutAt` / `flickerAt` each draws.
- `Sim.event(kind?)`: one scene at a time, tidies itself at its length, refused during an alarm or in a room with no door; `Sim.onEvent` is the hook for step 7, `EVENTS`/`EVENT_KINDS` the list step 6 toggles. Events touch no thread, ticket or turn; a thinking seat never leaves its desk.
- Scenes: duck walks the hall; meteor streaks past the window, lamps flicker, a crater, the idle crowd at the window; power cut blacks out the floor with a candle and applause; zoo's open day with van, monkey, penguin, a goat that eats a corkboard note, and Scharlach chasing with a net. The drill is reused unchanged and now has Scharlach calling it.
- `e` in the sandbox plays one (falls back to the old stand-in in the rail room).

Not done (plan's open items): Nina/Argos reactions in the zoo and the blackout monitor glow — skipped, no fitting existing pet mode; step 7 owns reactions.

Checked: `mise run check` exit 0 (office 505 pass, golden hashes unchanged); `office/test/events.test.ts` 18 tests, written red first.
