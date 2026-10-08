## Verdict: APPROVE

### Diff reviewed
`office/kit/homeart.ts`, `office/test/homeart.test.ts`, `office/tui/main.ts`, `office/AGENTS.md` — commits 037c00e and d8b1b35 on `work/whimsy-weather-comes-inside-7`.

### Prior QA findings (nolan, against cf31933) — both fixed
- **Rain spilling past the tile bottom:** the rain loop stops at `j < TILE - 1`, and the last 2px streak ends inside the tile. `rain and snow stay inside the tile` paints on a larger canvas and asserts every byte outside the tile is 0.
- **Amber snow:** snow now uses `ROLE.prose`, not the fence colour. `snow is pale` asserts every changed pixel has blue > 150, and that at least one pixel changed.

### Checked
- Only `garden` takes weather (`t.kind === "garden"` guard). `only the garden is out in it` pins every other kind unchanged under snow.
- Clear, partly, cloudy, fog, null and undefined leave the garden byte-identical. Storm renders the same as rain.
- `weather` is optional on `paintTile` and `HomeView`, so existing callers are untouched. The TUI passes `a.weather?.kind`.
- `bun test test/homeart.test.ts` run here: 13 pass, 0 fail. The server's verify check (`mise run check`) is recorded as exit 0 on the branch.
- `office/AGENTS.md` is updated in the same change.

### Scope (not blocking)
Garden tile in the build grid only. The dog refusing to go out needs the pets work, and weather in the room itself needs #43. Both were deferred openly in the build thread.

### Process note
Not a branch issue: nolan's QA rpc calls hit the live node, which set the `build_mode` flag and overwrote the live weather with a fake "Test rain". That is open with the operator, and the flag and weather still need resetting.