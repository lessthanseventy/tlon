APPROVE — loadHome: carry unknown tile kinds opaque (6718151)

Verified: read the diff and office/tui/home.ts; `bun test test/home.test.ts` in office/ → 27 pass, 0 fail.

- saveHome re-reads the file and appends tiles whose `kind` is a string not in CATALOGUE. loadHome still filters them out, so render/connected()/bounds never see them; the save is idempotent (unknown tiles are never in home.tiles, so no duplication).
- Known-kind tiles with a bad `at`, and kind-less tiles, are still dropped as before; the old test is narrowed accordingly and a new round-trip test covers the carry.
- Failure paths stay inside the existing try/catch (a blocked home still doesn't throw).

Non-blocking: one extra readFileSync per save (per user build write, negligible); unknown tiles carried are whatever is on disk at save time, which is right for an opaque passthrough.
