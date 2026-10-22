Toy: the weird end of the parts catalogue (ticket #98)

Ten new parts in `office/kit/parts.ts`, data only — `figure()` is untouched:
head: `duck` (hat), `fishbowl`, `cone`, `stormcloud` (rains on its wearer), `halo` (a `glow` dial, bright/dim, for the host to flicker), `plantpot`, `ufo` (hovers); neck: `snail` (on the shoulder); hand: `bananaphone`, `partyhorn` (a `toot` dial draws the streamer). The balloon at the wrist already existed.

Not in this change: the behaviours (halo flicker cycling, the horn tooting on a high-five) — the dials are there for a sim hook.

Checked: `test/weird-parts.test.ts` (red before the parts, green after); the generic parts, stable-looks and WCAG tests pass over the new parts; `tsc --noEmit` clean.
