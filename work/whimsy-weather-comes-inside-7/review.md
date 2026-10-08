VERDICT: approve

Reviewed 037c00e (4 files: homeart.ts, main.ts, test, office/AGENTS.md) by reading the diff. I did not re-run the gate. The server's verify stage recorded `mise run check` green.

- Scope matches the recorded decisions: weather appears only on the garden tile in the build grid. The dog refusal (needs the pets work) and in-room weather (needs #43) are deferred, and the commit message and thread say so.
- `paintTile` and `renderHome` take an optional weather kind. Existing callers are unaffected. Non-garden tiles are untouched, and `null` or `undefined` weather draws nothing extra.
- `main.ts` passes `a.weather?.kind` with optional chaining, so a missing feed is safe.
- Rain and storm share one painter. Snow caps the top row and flecks the ground. Pixel loops stay inside `TILE`.
- `office/AGENTS.md` was updated in the same commit, as the repo law requires.
- Tests were added in `office/test/homeart.test.ts`, written before the code per the thread.

Nits (non-blocking):
- `weather` is typed `string`, not the feed's kind union. Typing it from `Agents.weather.kind` would catch typos, but this is not worth a round-trip.
- Storm and rain look identical on the tile. That is fine for now.
