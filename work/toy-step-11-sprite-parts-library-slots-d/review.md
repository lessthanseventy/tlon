APPROVE — sprite parts library, slots, dials (thread 220)

Read the diff on office/kit/{parts,sprites,draw}.ts and tui/main.ts, plus the AGENTS.md change. I did not re-run the gate. The thread's recorded `mise run check` run shows exit 0.

Checked:
- Parts are data in `PARTS` and `figure()` has no per-part branch. `lookOf` is untouched, so existing looks are not restyled. `rollLook` is only called from the look card.
- `overlay` skips rows past the body height, so tall parts on the short build (cape rows to 17, 18 rows) are safe.
- `_` clears the pixel and `behind` paints only the clear pixels, so back-slot gear sits behind the body from the front and side. Hats clear hair only outside their crown, as intended.
- `heightOf` is used for both the draw top and the hit box, so the two stay in step. A custom look keeps the average build.
- `dialsOf` falls back to the first option for an unknown dial value, and `gearOf` returns undefined for a stale part id, so an old looks.json cannot crash the draw. The `drawn` cache key covers id plus dials.
- `LookOverride` is `Partial<Look>`, so `body` and `parts` persist through looks.json with no change to looks.ts.
- The docs are updated in the same change.

No blocking findings.