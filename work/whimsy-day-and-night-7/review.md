VERDICT: request_changes

Reviewed commit 79ea6dd (office/kit/daylight.ts, rooms/wide.ts, tests) against §7: "Day and night: the floor's light follows the real clock; lamps come on tile by tile; a pet asleep at night, you in pyjamas after clock-out." I read the diff and surrounding code; I did not run the suite (the server's verify already recorded green on `mise run check`).

What is right
- `darkness()` uses the same hours as the windows' sky (dusk 18:30–20:30, dawn 6:00–7:30). The ramp is continuous and tested.
- Pet bedtime is gated on idle state (sit, no path, no errand, no fuss), so it never interrupts a walk. Clock-dependent existing tests are pinned to hour 16; golden hashes regenerated deliberately.

Must fix
1. Pyjamas are missing and the commit doesn't say so. §7 has four parts; three are delivered. daneri flagged the "clock-out" ambiguity on the thread, but neither the commit nor AGENTS.md records the gap. Either add pyjamas (night hours as clock-out, as daneri proposed) or state plainly that they are deferred to a follow-up.
2. Four of the five "lamps" are not lamps. `nightfall` (wide.ts:324) hardcodes `[50,126]`, `[M0+MW/2,90]`, `[width-30,130]`, `[L0+60,160]`. The only lamp in the room is the lounge one near `L0+14,85` (grep finds no other lamp sprite). At night, warm pools will appear on bare floor or whatever sits there. Light real furniture, with positions taken from the plan/layout, or limit it to what exists.

Should fix
3. The dim is applied last, over everything below BAND including the windows, whose sky is already night-coloured. Check legibility of canvas-drawn text and the windows at full dark (office WCAG/themes rule), or dim before the windows/overlays.
4. The wide-room test only asserts night luminance < 0.85 × day. That passes for a dim that crushes the UI. Add a lower bound, and assert that a lit-lamp pixel is brighter than the same pixel without lamps.

Nits
- `season()` still uses `night = h>=19||h<6`, which differs from `darkness` (full dark from 20.5). Use one shared predicate for night.
- `bedtime` calls `Math.random()` in `step`, which breaks determinism for any seeded test that doesn't pin the hour. Existing tests are pinned, but it is a trap for the next one.