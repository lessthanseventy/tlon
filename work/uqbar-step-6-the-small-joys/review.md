Reviewer note: no free reviewer at the builder's grade (greybeard); tzinacan reviewed one grade down. Weigh accordingly.

# Review: uqbar-step-6-the-small-joys (13a8ff5)

**Verdict: request_changes** — one real bug in the swat, one-line fix.

## Blocking
- **A swat strands Nina's errand and it fires later at the wrong place.** `office/rooms/wide.ts` `stepVolume` sets `c.mode = "play"; c.path = []` but leaves `c.errand` set. An errand only completes in `Sim.stepCat` (`kit/sim.ts:332`) when a walk's path empties with `c.errand` non-null, so:
  1. Nina is carrying a letter/cheer/keys/drink (`mode "walk"`, errand set).
  2. The book flies low over her; she is swatted: path cleared, mode `play`, errand still set.
  3. Play expires, she wanders to any idle destination; when that walk ends, `!c.path.length && c.errand` is true and she "delivers" the letter/cheer/keys there: emote and line on the host, wherever she happens to be.
  Same hazard for `mode "zoom"` (swat overwrites the zoomies mid-state). Fix: don't swat her while she is on an errand or in zoomies.

  ```diff
  -    if (c.mode !== "sleep" && this.tick >= this.swatQuiet && swatted(this.book, this.book.flying, c)) {
  +    if (c.mode !== "sleep" && c.mode !== "zoom" && !c.errand && this.tick >= this.swatQuiet && swatted(this.book, this.book.flying, c)) {
  ```
  Add a test in `office/test/uqbar.test.ts`: errand set + book flying over her → `cat.mode` stays `walk`, `errand` intact, no flinch.

## Spec compliance (checked against the diff)
- Fallen spine: `fallen` re-set whenever `a.uqbar` absent; cleared only by a settled reader (`STRAIGHTEN` ticks in `peopleAt("read")`); `drawShelf` keys on `!!a.uqbar && fallen`. OK.
- Book shut for `FLINCH` ticks via `drawBook(..., shut)`. OK.
- Dog-ear: `fly` returns `caughtNth(...)`; TUI keeps `earmarked` by `earmarkOf(tid, at, who)`; Reader draws 🐾 via optional `dogeared`. OK.
- `office/AGENTS.md` updated in the same change. OK.

## Verified
- `bun test test/uqbar.test.ts test/dogear.test.ts`: 31 pass, 0 fail (run here, on this tree).
- Read `kit/sim.ts` `stepCat` and the `Cat` type to find the errand issue.
- Not run: `tsc`, `mise run check` (earlier verify recorded exit 0; not re-run by me).

## Non-blocking (follow-ups)
- Dog-ears live in the TUI process only; a restart forgets them.
