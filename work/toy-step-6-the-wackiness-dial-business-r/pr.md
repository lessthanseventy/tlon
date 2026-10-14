# office: the wackiness dial — business → rimworld, with toggles (toy step 6)

Closes #57. One preset (`business` | `casual` | `party` | `rimworld`) over individual dials, with per-dial
overrides, remembered in `office.json`. Choosing a preset sets the dials; touching one shows the preset as
`(custom)`; an override holds under any preset (state is `{mode, preset, overrides}`, "custom" is derived).

- `kit/whimsy.ts` presets/dials/resolve/parse, `kit/whimsy-file.ts` load/save (never throws).
- Sim honours the dials: a spontaneous-event scheduler (nothing fired events on its own before), event
  toggles (keyed events too), doorbell off/busy, pets asleep + silent (Nina and Argos, no antics).
- rimworld: events chain (zoo→drill→power→duck, depth ≤3), severity scales scenes, a red build sours a
  coworker's idle emotes for the afternoon — room-local, written nowhere.
- Wackiness card (finder: "the wackiness dial", `Z` on the settings card); banter gate in `chatter()`.
- The one rule: the work is never touched — `test/whimsy-work-untouched.test.ts`.
- Seeded golden frames unchanged: the scheduler and gates draw no `Math.random` when the answer is "no".

Not done, named: the server still writes banter the office hides (new ticket); `souls` and `weirdness`
dials are stored but have no seam yet (#323, #97/#98) and the card says "not wired yet". `play("event")`
now also plays nothing when every event is off (part of #354).

How checked: test-first per task; `mise run office:check` exit 0, 645 tests at 03:00 and 15:00; `mise run
check:names` exit 0. Not driven live in the wide room (kitty graphics needed; same gap as #161/#162).
